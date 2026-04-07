-- Fix stock_movements_view classification and reference resolution.
-- This prevents movement-row UUIDs from showing as references,
-- resolves invoice numbers for sales/purchases, and avoids
-- mislabeling legacy rows as manual when the reference already
-- identifies a sales or purchase document.

drop view if exists stock_movements_view cascade;

create view stock_movements_view as
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
	from stock_movements sm
	left join products p
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
			when coalesce(md.raw_movement_type, '') in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import', 'adjustment', 'inventory_adjust', 'inventory_adjustment') then 'adjustment'
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
			else null::uuid
		end as reference_id,
		case
			when md.document_type = 'sales_invoice' then coalesce(nullif(si.invoice_number, ''), md.reference)
			when md.document_type = 'purchase_invoice' then coalesce(nullif(pi.invoice_number, ''), md.reference)
			when md.document_type = 'mechanic_job' then coalesce(nullif(mj.job_number, ''), md.reference)
			when nullif(trim(coalesce(md.reference, '')), '') is not null then md.reference
			when nullif(trim(coalesce(md.notes, '')), '') is not null then md.notes
			else null::text
		end as reference_number,
		md.quantity,
		md.notes,
		md.created_by,
		md.created_at,
		md.tenant_id
	from movement_documents md
	left join sales_invoices si
		on md.document_type = 'sales_invoice'
	 and md.document_id = si.id
	 and md.tenant_id = si.tenant_id
	left join purchase_invoices pi
		on md.document_type = 'purchase_invoice'
	 and md.document_id = pi.id
	 and md.tenant_id = pi.tenant_id
	left join mechanic_jobs mj
		on md.document_type = 'mechanic_job'
	 and md.document_id = mj.id
	 and md.tenant_id = mj.tenant_id
),
movements_with_running_stock as (
	select 
		m.*,
		greatest(coalesce(p.stock_quantity, 0), coalesce(p.inventory_qty, 0)) as current_stock,
		greatest(coalesce(p.stock_quantity, 0), coalesce(p.inventory_qty, 0)) - coalesce(
			sum(m.quantity) over (
				partition by m.product_id, m.tenant_id 
				order by m.created_at desc, m.id desc
				rows between unbounded preceding and 1 preceding
			), 
			0
		)::integer as calculated_stock_after
	from movements_with_resolution m
	left join products p
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

alter view stock_movements_view set (security_invoker = on);
