-- Canonical source-document vocabulary for purchase evidence and a direct
-- local/emergency capture path. Existing invoices retain their historical
-- behavior as tax invoices; no purchase, payment, receipt, stock movement or
-- accounting row is created by this migration.
begin;

create table if not exists public.purchase_source_document_kinds (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  display_name text not null check (btrim(display_name) <> ''),
  description text not null check (btrim(description) <> ''),
  workflow_kind text not null check (
    workflow_kind in ('ordered_purchase', 'direct_purchase')
  ),
  sort_order smallint not null unique check (sort_order > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.purchase_source_document_kinds (
  code, display_name, description, workflow_kind, sort_order, is_active
) values
  (
    'tax_invoice',
    'Factura',
    'Documento tributario emitido como factura por el proveedor.',
    'ordered_purchase',
    10,
    true
  ),
  (
    'receipt',
    'Boleta',
    'Boleta de una compra directa, frecuente en comercios o talleres locales.',
    'direct_purchase',
    20,
    true
  ),
  (
    'ticket',
    'Ticket o vale',
    'Comprobante simple que acredita una compra directa.',
    'direct_purchase',
    30,
    true
  ),
  (
    'no_tax_document',
    'Sin documento tributario',
    'Compra real sin factura ni boleta; requiere conservar la evidencia disponible.',
    'direct_purchase',
    40,
    true
  ),
  (
    'other',
    'Otro comprobante',
    'Otro documento verdadero que respalda la compra.',
    'direct_purchase',
    50,
    true
  )
on conflict (code) do update
set display_name = excluded.display_name,
    description = excluded.description,
    workflow_kind = excluded.workflow_kind,
    sort_order = excluded.sort_order,
    is_active = excluded.is_active,
    updated_at = clock_timestamp();

alter table public.purchase_source_document_kinds enable row level security;

drop policy if exists purchase_source_document_kinds_authenticated_read
  on public.purchase_source_document_kinds;
create policy purchase_source_document_kinds_authenticated_read
  on public.purchase_source_document_kinds
  for select
  to authenticated
  using (true);

revoke all on public.purchase_source_document_kinds
  from public, anon, authenticated, service_role;
grant select on public.purchase_source_document_kinds
  to authenticated, service_role;

alter table public.purchase_invoices
  add column if not exists source_document_kind text;

update public.purchase_invoices
set source_document_kind = 'tax_invoice'
where source_document_kind is null;

alter table public.purchase_invoices
  alter column source_document_kind set default 'tax_invoice',
  alter column source_document_kind set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.purchase_invoices'::regclass
      and constraint_row.conname =
        'purchase_invoices_source_document_kind_fkey'
  ) then
    alter table public.purchase_invoices
      add constraint purchase_invoices_source_document_kind_fkey
      foreign key (source_document_kind)
      references public.purchase_source_document_kinds(code)
      on update restrict
      on delete restrict;
  end if;
end;
$$;

comment on column public.purchase_invoices.source_document_kind is
  'Server-owned vocabulary identifying the real supplier evidence: invoice, receipt, ticket, no-tax-document or another reviewed kind.';

create or replace view public.purchase_invoice_list_read_model_v2
with (security_invoker = true)
as
select
  legacy.id,
  legacy.tenant_id,
  legacy.invoice_number,
  legacy.supplier_id,
  legacy.supplier_name,
  legacy.supplier_rut,
  legacy.date,
  legacy.due_date,
  legacy.status,
  legacy.subtotal,
  legacy.tax,
  legacy.total,
  legacy.net_amount,
  legacy.paid_amount,
  legacy.balance,
  legacy.supplier_refunded_amount,
  legacy.credited_amount,
  legacy.supplier_credit_balance,
  legacy.prepayment_model,
  legacy.sent_date,
  legacy.confirmed_date,
  legacy.received_date,
  legacy.paid_date,
  legacy.items,
  legacy.created_at,
  legacy.updated_at,
  legacy.receipt_state,
  legacy.receipt_expected_quantity,
  legacy.receipt_accepted_quantity,
  legacy.receipt_reported_difference_quantity,
  legacy.receipt_resolved_difference_quantity,
  legacy.receipt_nonphysical_resolution_quantity,
  legacy.receipt_unresolved_difference_quantity,
  legacy.receipt_physical_remaining_quantity,
  legacy.receipt_remaining_quantity,
  legacy.receipt_count,
  legacy.receipt_latest_received_at,
  legacy.receipt_legacy_received,
  invoice.source_document_kind,
  kind.display_name as source_document_kind_label,
  kind.workflow_kind as source_document_workflow_kind
from public.purchase_invoice_list_read_model legacy
join public.purchase_invoices invoice
  on invoice.tenant_id = legacy.tenant_id
 and invoice.id = legacy.id
join public.purchase_source_document_kinds kind
  on kind.code = invoice.source_document_kind;

revoke all on public.purchase_invoice_list_read_model_v2
  from public, anon;
grant select on public.purchase_invoice_list_read_model_v2
  to authenticated, service_role;

comment on view public.purchase_invoice_list_read_model_v2 is
  'V1 financial and physical purchase snapshot plus the canonical source-document kind and label.';

-- Locality is a supplier-relationship fact, not something inferred from a
-- receipt or a legacy supplier default. Seed the vocabulary for explicit
-- review; do not create assignments automatically.
create or replace function public.seed_intelligent_purchasing_supplier_tags(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  insert into public.supplier_tag_definitions (
    tenant_id, code, label, description, is_system
  ) values
    (
      p_tenant_id,
      'local_workshop',
      'Taller local',
      'Taller o comercio cercano que puede suministrar repuestos localmente.',
      true
    ),
    (
      p_tenant_id,
      'emergency_local',
      'Alternativa local de rescate',
      'Proveedor local validado para resolver compras urgentes.',
      true
    )
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();
end;
$$;

revoke all on function public.seed_intelligent_purchasing_supplier_tags(uuid)
  from public, anon, authenticated, service_role;
grant execute on function
  public.seed_intelligent_purchasing_supplier_tags(uuid)
  to service_role;

select public.seed_intelligent_purchasing_supplier_tags(tenant.id)
from public.tenants tenant;

create or replace function
  public.seed_intelligent_purchasing_supplier_tags_on_tenant()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.seed_intelligent_purchasing_supplier_tags(new.id);
  return new;
end;
$$;

revoke all on function
  public.seed_intelligent_purchasing_supplier_tags_on_tenant()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_seed_intelligent_purchasing_supplier_tags_on_tenant
  on public.tenants;
create trigger trg_seed_intelligent_purchasing_supplier_tags_on_tenant
  after insert on public.tenants
  for each row
  execute function
    public.seed_intelligent_purchasing_supplier_tags_on_tenant();

commit;
