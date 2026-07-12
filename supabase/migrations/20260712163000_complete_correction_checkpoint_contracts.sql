-- Deployment status: DEPLOYED 2026-07-12 to xzdvtzdqjeyqxnkqprtf.
-- Authenticated rollback smoke covered supplier/customer return + credit-note
-- create/void (8 complete contracts, balanced journals, exact restored stock).
-- Completes ordered trace phases for professional returns, credit notes,
-- quarantine resolutions, and cash settlement without changing their business
-- amounts. Physical-return value journals are posted before invariants.

begin;

create or replace function public.post_physical_return_inventory_journal(p_operation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_op public.inventory_accounting_operations%rowtype;
  v_amount numeric := 0;
  v_restock_amount numeric := 0;
  v_quarantine_amount numeric := 0;
  v_scrap_amount numeric := 0;
  v_entry uuid := gen_random_uuid();
  v_source_entry uuid;
  v_existing_void_entry uuid;
  v_account_a uuid;
  v_account_b uuid;
  v_quarantine_account uuid;
  v_loss_account uuid;
  v_desc text;
  v_line record;
begin
  select * into v_op
  from public.inventory_accounting_operations
  where id = p_operation_id;

  if not found
     or v_op.document_type not in ('purchase_supplier_return', 'sales_return')
     or v_op.outcome not in ('started', 'completed') then
    return;
  end if;

  if v_op.document_type = 'purchase_supplier_return' then
    if v_op.action = 'create' then
      if exists (
        select 1 from public.purchase_supplier_returns
        where id = v_op.document_id and inventory_journal_entry_id is not null
      ) then
        return;
      end if;
      select public.clp_round(coalesce(sum(line.returned_quantity * receipt_line.unit_cost), 0))
      into v_amount
      from public.purchase_supplier_return_lines line
      join public.purchase_receipt_lines receipt_line
        on receipt_line.id = line.purchase_receipt_line_id
      where line.supplier_return_id = v_op.document_id;
      if v_amount <= 0 then return; end if;
      v_account_a := public.ensure_account(v_op.tenant_id, '1145', 'Reclamos a Proveedores', 'asset', 'currentAsset', 'Mercadería devuelta pendiente de crédito', null);
      v_account_b := public.ensure_account(v_op.tenant_id, '1105', 'Inventarios', 'asset', 'currentAsset', 'Valor del inventario', null);
      v_desc := 'Devolución física a proveedor';
      insert into public.journal_entries(
        id,tenant_id,entry_number,entry_date,description,type,source_module,
        source_reference,status,total_debit,total_credit,operation_id,
        source_document_type,source_document_id,created_by,created_at,updated_at
      ) values (
        v_entry,v_op.tenant_id,public.get_next_document_number(v_op.tenant_id,'journal_entry'),
        now(),v_desc,'inventory_return','purchase_supplier_returns',v_op.document_id::text,
        'posted',v_amount,v_amount,v_op.id,'purchase_supplier_return',v_op.document_id,
        v_op.actor_id,now(),now()
      );
      insert into public.journal_lines(
        id,tenant_id,entry_id,account_id,account_code,account_name,description,
        debit_amount,credit_amount,created_at,updated_at
      ) values
        (gen_random_uuid(),v_op.tenant_id,v_entry,v_account_a,'1145','Reclamos a Proveedores',v_desc,v_amount,0,now(),now()),
        (gen_random_uuid(),v_op.tenant_id,v_entry,v_account_b,'1105','Inventarios',v_desc,0,v_amount,now(),now());
      update public.purchase_supplier_returns
      set inventory_journal_entry_id = v_entry
      where id = v_op.document_id;
    else
      select inventory_journal_entry_id, void_inventory_journal_entry_id
      into v_source_entry, v_existing_void_entry
      from public.purchase_supplier_returns
      where id = v_op.document_id;
      if v_source_entry is null or v_existing_void_entry is not null then return; end if;
    end if;
  else
    if v_op.action = 'create' then
      if exists (
        select 1 from public.sales_returns
        where id = v_op.document_id and inventory_journal_entry_id is not null
      ) then
        return;
      end if;
      select
        public.clp_round(coalesce(sum(line.returned_quantity * coalesce(nullif(line.line_snapshot->>'cost','')::numeric,0)) filter (where line.disposition='restock'),0)),
        public.clp_round(coalesce(sum(line.returned_quantity * coalesce(nullif(line.line_snapshot->>'cost','')::numeric,0)) filter (where line.disposition='quarantine'),0)),
        public.clp_round(coalesce(sum(line.returned_quantity * coalesce(nullif(line.line_snapshot->>'cost','')::numeric,0)) filter (where line.disposition='scrap'),0))
      into v_restock_amount, v_quarantine_amount, v_scrap_amount
      from public.sales_return_lines line
      where line.sales_return_id = v_op.document_id;
      v_amount := v_restock_amount + v_quarantine_amount + v_scrap_amount;
      if v_amount <= 0 then return; end if;
      v_account_a := public.ensure_account(v_op.tenant_id,'1105','Inventarios','asset','currentAsset','Valor del inventario',null);
      v_quarantine_account := public.ensure_account(v_op.tenant_id,'1106','Inventario en Cuarentena','asset','currentAsset','Devoluciones recibidas pendientes de inspección',null);
      v_loss_account := public.ensure_account(v_op.tenant_id,'5205','Pérdidas de Inventario','expense','operatingExpense','Mercadería dañada o no recuperable',null);
      v_account_b := public.ensure_account(v_op.tenant_id,'5100','Costo de Ventas','expense','costOfGoodsSold','Costo de ventas',null);
      v_desc := 'Custodia física por devolución de cliente';
      insert into public.journal_entries(
        id,tenant_id,entry_number,entry_date,description,type,source_module,
        source_reference,status,total_debit,total_credit,operation_id,
        source_document_type,source_document_id,created_by,created_at,updated_at
      ) values (
        v_entry,v_op.tenant_id,public.get_next_document_number(v_op.tenant_id,'journal_entry'),
        now(),v_desc,'inventory_return','sales_returns',v_op.document_id::text,
        'posted',v_amount,v_amount,v_op.id,'sales_return',v_op.document_id,
        v_op.actor_id,now(),now()
      );
      insert into public.journal_lines(
        id,tenant_id,entry_id,account_id,account_code,account_name,description,
        debit_amount,credit_amount,created_at,updated_at
      )
      select gen_random_uuid(),v_op.tenant_id,v_entry,v_account_a,'1105','Inventarios',v_desc,v_restock_amount,0,now(),now() where v_restock_amount>0
      union all select gen_random_uuid(),v_op.tenant_id,v_entry,v_quarantine_account,'1106','Inventario en Cuarentena',v_desc,v_quarantine_amount,0,now(),now() where v_quarantine_amount>0
      union all select gen_random_uuid(),v_op.tenant_id,v_entry,v_loss_account,'5205','Pérdidas de Inventario',v_desc,v_scrap_amount,0,now(),now() where v_scrap_amount>0
      union all select gen_random_uuid(),v_op.tenant_id,v_entry,v_account_b,'5100','Costo de Ventas',v_desc,0,v_amount,now(),now();
      update public.sales_returns
      set inventory_journal_entry_id = v_entry
      where id = v_op.document_id;
    else
      select inventory_journal_entry_id, void_inventory_journal_entry_id
      into v_source_entry, v_existing_void_entry
      from public.sales_returns
      where id = v_op.document_id;
      if v_source_entry is null or v_existing_void_entry is not null then return; end if;
    end if;
  end if;

  if v_op.action = 'void' then
    select total_debit into v_amount
    from public.journal_entries
    where id = v_source_entry;
    v_desc := 'Anulación de valor por devolución física';
    insert into public.journal_entries(
      id,tenant_id,entry_number,entry_date,description,type,source_module,
      source_reference,status,total_debit,total_credit,operation_id,
      source_document_type,source_document_id,created_by,reversal_of_id,
      created_at,updated_at
    ) values (
      v_entry,v_op.tenant_id,public.get_next_document_number(v_op.tenant_id,'journal_entry'),
      now(),v_desc,'inventory_return_void',v_op.document_type||'s',v_op.document_id::text,
      'posted',v_amount,v_amount,v_op.id,v_op.document_type,v_op.document_id,
      v_op.actor_id,v_source_entry,now(),now()
    );
    for v_line in select * from public.journal_lines where entry_id = v_source_entry loop
      insert into public.journal_lines(
        id,tenant_id,entry_id,account_id,account_code,account_name,description,
        debit_amount,credit_amount,created_at,updated_at
      ) values (
        gen_random_uuid(),v_op.tenant_id,v_entry,v_line.account_id,v_line.account_code,
        v_line.account_name,v_desc,v_line.credit_amount,v_line.debit_amount,now(),now()
      );
    end loop;
    if v_op.document_type = 'purchase_supplier_return' then
      update public.purchase_supplier_returns set void_inventory_journal_entry_id=v_entry where id=v_op.document_id;
    else
      update public.sales_returns set void_inventory_journal_entry_id=v_entry where id=v_op.document_id;
    end if;
  end if;

  perform public.append_inventory_accounting_checkpoint(
    v_op.id,
    case when v_op.action='void' then 'journal_reversed' else 'journal_posted' end,
    'completed','journal_entry',v_entry,jsonb_build_object('inventory_value',v_amount)
  );
end;
$$;

create or replace function public.checkpoint_journal_entry_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation_id uuid;
  v_original_operation_id uuid;
  v_context_operation_text text;
  v_payload jsonb;
  v_phase text;
begin
  if tg_op = 'DELETE' then
    v_original_operation_id := old.operation_id;
    v_context_operation_text := nullif(current_setting('app.inventory_operation_id', true), '');
    v_operation_id := coalesce(
      case when v_context_operation_text is null then null else v_context_operation_text::uuid end,
      v_original_operation_id
    );
    v_phase := 'journal_reversed';
  else
    v_operation_id := new.operation_id;
    v_phase := case when new.reversal_of_id is not null then 'journal_reversed' else 'journal_posted' end;
  end if;

  if v_operation_id is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- These commands append their journal checkpoint at the deliberate contract
  -- position after inventory/movement/accounting planning. Avoid an earlier
  -- generic checkpoint merely because the journal row is inserted first.
  if tg_op <> 'DELETE' and exists (
    select 1
    from public.inventory_accounting_operations operation
    where operation.id = v_operation_id
      and operation.document_type in (
        'purchase_supplier_return','sales_return','purchase_credit_note','sales_credit_note',
        'sales_customer_refund','purchase_supplier_refund','sales_return_quarantine_resolution'
      )
  ) then
    return new;
  end if;

  v_payload := case
    when tg_op = 'DELETE' then jsonb_build_object(
      'entry_number',old.entry_number,
      'source_module',old.source_module,
      'source_reference',old.source_reference,
      'total_debit',old.total_debit,
      'total_credit',old.total_credit,
      'reversed_journal_operation_id',v_original_operation_id,
      'deleted_snapshot',to_jsonb(old)
    )
    else jsonb_build_object(
      'entry_number',new.entry_number,
      'source_module',new.source_module,
      'source_reference',new.source_reference,
      'total_debit',new.total_debit,
      'total_credit',new.total_credit,
      'reversal_of_id',new.reversal_of_id
    )
  end;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,v_phase,'completed','journal_entry',
    case when tg_op='DELETE' then old.id else new.id end,v_payload
  );

  if tg_op='DELETE'
     and v_original_operation_id is not null
     and v_original_operation_id is distinct from v_operation_id then
    perform public.append_inventory_accounting_checkpoint(
      v_original_operation_id,'journal_reversed','completed','journal_entry',old.id,
      jsonb_build_object('entry_number',old.entry_number,'reversed_by_operation_id',v_operation_id)
    );
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

comment on function public.checkpoint_journal_entry_trace() is
  'Classifies inserted reversal journals by reversal_of_id instead of mislabeling them as ordinary postings.';

create or replace function public.prepare_professional_correction_operation_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.document_type in (
    'purchase_supplier_return','sales_return','purchase_credit_note','sales_credit_note',
    'sales_customer_refund','purchase_supplier_refund','sales_return_quarantine_resolution'
  ) then
    perform public.append_inventory_accounting_checkpoint(
      new.id,'accepted','started',new.document_type,new.document_id,
      jsonb_build_object('action',new.action,'generated_by','professional_checkpoint_contract')
    );
  end if;
  return new;
end;
$$;

create or replace function public.prepare_professional_correction_checkpoint()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation public.inventory_accounting_operations%rowtype;
begin
  select * into v_operation
  from public.inventory_accounting_operations
  where id = new.operation_id and tenant_id = new.tenant_id;
  if not found or v_operation.document_type not in (
    'purchase_supplier_return','sales_return','purchase_credit_note','sales_credit_note',
    'sales_customer_refund','purchase_supplier_refund','sales_return_quarantine_resolution'
  ) then
    return new;
  end if;

  if new.phase = 'accepted' then
    if not exists(select 1 from public.inventory_accounting_checkpoints where operation_id=new.operation_id and phase='source_snapshotted') then
      insert into public.inventory_accounting_checkpoints(
        tenant_id,operation_id,phase,outcome,entity_type,entity_id,payload
      ) values (
        new.tenant_id,new.operation_id,'source_snapshotted','completed',
        new.entity_type,new.entity_id,
        jsonb_build_object(
          'snapshot_owner','immutable_document_lines_and_operation_context',
          'operation_context',v_operation.context,
          'action',v_operation.action
        )
      );
    end if;
    if not exists(select 1 from public.inventory_accounting_checkpoints where operation_id=new.operation_id and phase='inventory_planned') then
      insert into public.inventory_accounting_checkpoints(
        tenant_id,operation_id,phase,outcome,entity_type,entity_id,payload
      ) values (
        new.tenant_id,new.operation_id,'inventory_planned','completed',
        v_operation.document_type,v_operation.document_id,
        jsonb_build_object(
          'stock_owner',v_operation.document_type,
          'financial_only',v_operation.document_type in (
            'purchase_credit_note','sales_credit_note','sales_customer_refund','purchase_supplier_refund'
          ),
          'action',v_operation.action
        )
      );
    end if;
  end if;

  if new.phase = 'accounting_planned'
     and v_operation.document_type in ('purchase_supplier_return','sales_return') then
    new.outcome := 'completed';
    new.payload := coalesce(new.payload,'{}'::jsonb) || jsonb_build_object(
      'journal_policy','post_inventory_value_or_explicit_zero_value_noop',
      'financial_credit_separate',true,
      'action',v_operation.action
    );
  end if;
  return new;
end;
$$;

create or replace function public.complete_professional_correction_checkpoint()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation public.inventory_accounting_operations%rowtype;
  v_journal_phase text;
begin
  select * into v_operation
  from public.inventory_accounting_operations
  where id = new.operation_id and tenant_id = new.tenant_id;
  if not found or v_operation.document_type not in (
    'purchase_supplier_return','sales_return','purchase_credit_note','sales_credit_note',
    'sales_customer_refund','purchase_supplier_refund','sales_return_quarantine_resolution'
  ) then
    return new;
  end if;

  if new.phase = 'inventory_applied'
     and new.entity_type = v_operation.document_type then
    if not exists(
      select 1 from public.inventory_accounting_checkpoints
      where operation_id=new.operation_id
        and phase='movement_recorded'
        and entity_type=v_operation.document_type
    ) then
      perform public.append_inventory_accounting_checkpoint(
        new.operation_id,'movement_recorded','completed',v_operation.document_type,
        v_operation.document_id,
        jsonb_build_object(
          'movement_count',(select count(*) from public.stock_movements where operation_id=new.operation_id),
          'explicit_zero_stock',not exists(select 1 from public.stock_movements where operation_id=new.operation_id)
        )
      );
    end if;
    if v_operation.document_type not in ('purchase_supplier_return','sales_return')
       and not exists(select 1 from public.inventory_accounting_checkpoints where operation_id=new.operation_id and phase='accounting_planned') then
      perform public.append_inventory_accounting_checkpoint(
        new.operation_id,'accounting_planned','completed',v_operation.document_type,
        v_operation.document_id,
        jsonb_build_object(
          'journal_expected',true,
          'stock_effect','none_or_separately_recorded',
          'action',v_operation.action
        )
      );
    end if;
  end if;

  if new.phase = 'accounting_planned'
     and v_operation.document_type in ('purchase_supplier_return','sales_return') then
    perform public.post_physical_return_inventory_journal(new.operation_id);
    v_journal_phase := case when v_operation.action='void' then 'journal_reversed' else 'journal_posted' end;
    if not exists(
      select 1 from public.inventory_accounting_checkpoints
      where operation_id=new.operation_id and phase=v_journal_phase
    ) then
      perform public.append_inventory_accounting_checkpoint(
        new.operation_id,v_journal_phase,'completed',v_operation.document_type,
        v_operation.document_id,
        jsonb_build_object('journal_count',0,'not_required',true,'reason','zero_inventory_value')
      );
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.post_physical_return_inventory_journal(uuid) from public,anon,authenticated;
revoke all on function public.prepare_professional_correction_operation_trace() from public,anon,authenticated;
revoke all on function public.prepare_professional_correction_checkpoint() from public,anon,authenticated;
revoke all on function public.complete_professional_correction_checkpoint() from public,anon,authenticated;

drop trigger if exists trg_prepare_professional_correction_void_trace
  on public.inventory_accounting_operations;
drop function if exists public.prepare_professional_correction_void_trace();

drop trigger if exists trg_prepare_professional_correction_operation_trace
  on public.inventory_accounting_operations;
create trigger trg_prepare_professional_correction_operation_trace
  after insert on public.inventory_accounting_operations
  for each row execute function public.prepare_professional_correction_operation_trace();

drop trigger if exists trg_prepare_professional_correction_checkpoint
  on public.inventory_accounting_checkpoints;
create trigger trg_prepare_professional_correction_checkpoint
  before insert on public.inventory_accounting_checkpoints
  for each row execute function public.prepare_professional_correction_checkpoint();

drop trigger if exists trg_complete_professional_correction_checkpoint
  on public.inventory_accounting_checkpoints;
create trigger trg_complete_professional_correction_checkpoint
  after insert on public.inventory_accounting_checkpoints
  for each row execute function public.complete_professional_correction_checkpoint();

comment on function public.complete_professional_correction_checkpoint() is
  'Completes ordered movement/accounting trace phases and posts physical-return value journals before invariant verification.';

create or replace view public.professional_correction_trace_contract_view
with (security_invoker = true)
as
with first_phase as (
  select
    checkpoint.operation_id,
    checkpoint.phase,
    min(checkpoint.id) as first_id
  from public.inventory_accounting_checkpoints checkpoint
  group by checkpoint.operation_id, checkpoint.phase
), contracts as (
  select
    operation.id as operation_id,
    string_agg(first_phase.phase, ',' order by first_phase.first_id) as phase_contract
  from public.inventory_accounting_operations operation
  left join first_phase on first_phase.operation_id = operation.id
  where operation.document_type in (
    'purchase_supplier_return','sales_return','purchase_credit_note','sales_credit_note',
    'sales_customer_refund','purchase_supplier_refund','sales_return_quarantine_resolution'
  )
  group by operation.id
)
select
  operation.tenant_id,
  operation.id as operation_id,
  operation.document_type,
  operation.document_id,
  operation.action,
  operation.outcome,
  contracts.phase_contract,
  format(
    'accepted,source_snapshotted,inventory_planned,inventory_applied,movement_recorded,accounting_planned,%s,invariants_verified,completed',
    case when operation.action = 'void' then 'journal_reversed' else 'journal_posted' end
  ) as expected_phase_contract,
  contracts.phase_contract = format(
    'accepted,source_snapshotted,inventory_planned,inventory_applied,movement_recorded,accounting_planned,%s,invariants_verified,completed',
    case when operation.action = 'void' then 'journal_reversed' else 'journal_posted' end
  ) as contract_complete,
  operation.created_at
from public.inventory_accounting_operations operation
join contracts on contracts.operation_id = operation.id;

grant select on public.professional_correction_trace_contract_view to authenticated;

comment on view public.professional_correction_trace_contract_view is
  'Auditable first-occurrence phase contract for professional returns, credit notes, quarantine resolution, and cash settlement.';

commit;
