-- Deployment status: DEPLOYED 2026-07-11. Adds accounting ownership to physical returns.
begin;
alter table public.purchase_supplier_returns add column if not exists inventory_journal_entry_id uuid references public.journal_entries(id),add column if not exists void_inventory_journal_entry_id uuid references public.journal_entries(id);
alter table public.sales_returns add column if not exists inventory_journal_entry_id uuid references public.journal_entries(id),add column if not exists void_inventory_journal_entry_id uuid references public.journal_entries(id);

create or replace function public.post_physical_return_inventory_journal(p_operation_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_op public.inventory_accounting_operations%rowtype;v_amount numeric;v_restock_amount numeric:=0;v_quarantine_amount numeric:=0;v_scrap_amount numeric:=0;v_entry uuid:=gen_random_uuid();v_source_entry uuid;v_account_a uuid;v_account_b uuid;v_quarantine_account uuid;v_loss_account uuid;v_desc text;v_line record;
begin
 select * into v_op from public.inventory_accounting_operations where id=p_operation_id;if not found or v_op.outcome<>'completed'then return;end if;
 if v_op.document_type='purchase_supplier_return'then
  if v_op.action='create'then
   select public.clp_round(coalesce(sum(line.returned_quantity*receipt_line.unit_cost),0))into v_amount from public.purchase_supplier_return_lines line join public.purchase_receipt_lines receipt_line on receipt_line.id=line.purchase_receipt_line_id where line.supplier_return_id=v_op.document_id;
   if v_amount<=0 or exists(select 1 from public.purchase_supplier_returns where id=v_op.document_id and inventory_journal_entry_id is not null)then return;end if;
   v_account_a:=public.ensure_account(v_op.tenant_id,'1145','Reclamos a Proveedores','asset','currentAsset','Mercadería devuelta pendiente de crédito',null);v_account_b:=public.ensure_account(v_op.tenant_id,'1105','Inventarios','asset','currentAsset','Valor del inventario',null);v_desc:='Devolución física a proveedor';
   insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,created_at,updated_at)values(v_entry,v_op.tenant_id,public.get_next_document_number(v_op.tenant_id,'journal_entry'),now(),v_desc,'inventory_return','purchase_supplier_returns',v_op.document_id::text,'posted',v_amount,v_amount,v_op.id,'purchase_supplier_return',v_op.document_id,v_op.actor_id,now(),now());
   insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)values(gen_random_uuid(),v_op.tenant_id,v_entry,v_account_a,'1145','Reclamos a Proveedores',v_desc,v_amount,0,now(),now()),(gen_random_uuid(),v_op.tenant_id,v_entry,v_account_b,'1105','Inventarios',v_desc,0,v_amount,now(),now());
   update public.purchase_supplier_returns set inventory_journal_entry_id=v_entry where id=v_op.document_id;
  else
   select inventory_journal_entry_id into v_source_entry from public.purchase_supplier_returns where id=v_op.document_id;if v_source_entry is null then return;end if;
  end if;
 elsif v_op.document_type='sales_return'then
  if v_op.action='create'then
   select
    public.clp_round(coalesce(sum(line.returned_quantity*coalesce(nullif(line.line_snapshot->>'cost','')::numeric,0))filter(where line.disposition='restock'),0)),
    public.clp_round(coalesce(sum(line.returned_quantity*coalesce(nullif(line.line_snapshot->>'cost','')::numeric,0))filter(where line.disposition='quarantine'),0)),
    public.clp_round(coalesce(sum(line.returned_quantity*coalesce(nullif(line.line_snapshot->>'cost','')::numeric,0))filter(where line.disposition='scrap'),0))
   into v_restock_amount,v_quarantine_amount,v_scrap_amount
   from public.sales_return_lines line where line.sales_return_id=v_op.document_id;
   v_amount:=v_restock_amount+v_quarantine_amount+v_scrap_amount;
   if v_amount<=0 or exists(select 1 from public.sales_returns where id=v_op.document_id and inventory_journal_entry_id is not null)then return;end if;
   v_account_a:=public.ensure_account(v_op.tenant_id,'1105','Inventarios','asset','currentAsset','Valor del inventario',null);
   v_quarantine_account:=public.ensure_account(v_op.tenant_id,'1106','Inventario en Cuarentena','asset','currentAsset','Devoluciones recibidas pendientes de inspección',null);
   v_loss_account:=public.ensure_account(v_op.tenant_id,'5205','Pérdidas de Inventario','expense','operatingExpense','Mercadería dañada o no recuperable',null);
   v_account_b:=public.ensure_account(v_op.tenant_id,'5100','Costo de Ventas','expense','costOfGoodsSold','Costo de ventas',null);v_desc:='Custodia física por devolución de cliente';
   insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,created_at,updated_at)values(v_entry,v_op.tenant_id,public.get_next_document_number(v_op.tenant_id,'journal_entry'),now(),v_desc,'inventory_return','sales_returns',v_op.document_id::text,'posted',v_amount,v_amount,v_op.id,'sales_return',v_op.document_id,v_op.actor_id,now(),now());
   insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)
   select gen_random_uuid(),v_op.tenant_id,v_entry,v_account_a,'1105','Inventarios',v_desc,v_restock_amount,0,now(),now() where v_restock_amount>0
   union all select gen_random_uuid(),v_op.tenant_id,v_entry,v_quarantine_account,'1106','Inventario en Cuarentena',v_desc,v_quarantine_amount,0,now(),now() where v_quarantine_amount>0
   union all select gen_random_uuid(),v_op.tenant_id,v_entry,v_loss_account,'5205','Pérdidas de Inventario',v_desc,v_scrap_amount,0,now(),now() where v_scrap_amount>0
   union all select gen_random_uuid(),v_op.tenant_id,v_entry,v_account_b,'5100','Costo de Ventas',v_desc,0,v_amount,now(),now();
   update public.sales_returns set inventory_journal_entry_id=v_entry where id=v_op.document_id;
  else select inventory_journal_entry_id into v_source_entry from public.sales_returns where id=v_op.document_id;if v_source_entry is null then return;end if;
  end if;
 else return;end if;
 if v_op.action='void'and v_source_entry is not null then
  select total_debit into v_amount from public.journal_entries where id=v_source_entry;v_desc:='Anulación de valor por devolución física';
  insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,reversal_of_id,created_at,updated_at)values(v_entry,v_op.tenant_id,public.get_next_document_number(v_op.tenant_id,'journal_entry'),now(),v_desc,'inventory_return_void',v_op.document_type||'s',v_op.document_id::text,'posted',v_amount,v_amount,v_op.id,v_op.document_type,v_op.document_id,v_op.actor_id,v_source_entry,now(),now());
  for v_line in select * from public.journal_lines where entry_id=v_source_entry loop insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)values(gen_random_uuid(),v_op.tenant_id,v_entry,v_line.account_id,v_line.account_code,v_line.account_name,v_desc,v_line.credit_amount,v_line.debit_amount,now(),now());end loop;
  if v_op.document_type='purchase_supplier_return'then update public.purchase_supplier_returns set void_inventory_journal_entry_id=v_entry where id=v_op.document_id;else update public.sales_returns set void_inventory_journal_entry_id=v_entry where id=v_op.document_id;end if;
 end if;
 if v_entry is not null then perform public.append_inventory_accounting_checkpoint(v_op.id,case when v_op.action='void'then'journal_reversed'else'journal_posted'end,'completed','journal_entry',v_entry,jsonb_build_object('inventory_value',v_amount));end if;
end;$$;
create or replace function public.handle_completed_return_inventory_journal()returns trigger language plpgsql security definer set search_path=public as $$begin if new.outcome='completed'and old.outcome is distinct from'completed'and new.document_type in('purchase_supplier_return','sales_return')then perform public.post_physical_return_inventory_journal(new.id);end if;return new;end;$$;
drop trigger if exists trg_completed_return_inventory_journal on public.inventory_accounting_operations;create trigger trg_completed_return_inventory_journal after update of outcome on public.inventory_accounting_operations for each row execute function public.handle_completed_return_inventory_journal();
commit;
