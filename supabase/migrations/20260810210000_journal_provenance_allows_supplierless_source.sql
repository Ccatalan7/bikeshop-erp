-- Un gasto sin proveedor es legítimo, y confirmar una nómina depende de eso.
--
-- **Regresión introducida el 2026-08-08** por
-- `20260808210000_supplier_relationship_foundation.sql`, medida en producción el
-- 2026-08-10 conduciendo la app real: `Confirmar semana` moría con
-- `Canonical journal source is missing or outside tenant` (23514) y la
-- transacción entera se revertía, así que ninguna semana podía confirmarse y
-- ningún sueldo podía pagarse. Antes funcionaba: 69 líneas de nómina ya tienen
-- su gasto creado por este mismo camino.
--
-- **La causa.** `validate_supplier_journal_provenance` trata
-- `source_document_type = 'expense'` como documento de proveedor **siempre**, y
-- exige que `resolve_supplier_party_for_journal_source` devuelva una parte. Ese
-- resolutor une `expenses` con `suppliers` por `expense.supplier_id`, así que
-- devuelve `null` en dos situaciones que no se parecen en nada:
--
--   1. el documento no existe, o es de otro tenant  → violación de procedencia;
--   2. el documento existe y **no tiene proveedor** → un caso normal.
--
-- El sueldo de un trabajador es el segundo: no se le compra a un proveedor. Y
-- no es un caso de borde — en producción **79 de 137 gastos no tienen
-- proveedor**. El guard confundía las dos y bloqueaba la nómina completa.
--
-- **El arreglo conserva el guard y sólo le quita la ambigüedad**: si la parte no
-- resuelve, se comprueba si el documento fuente existe dentro del tenant. Si
-- existe, el asiento pasa —no nombra a ningún proveedor y no puede mentir sobre
-- uno—. Si no existe, sigue siendo la violación que este guard vino a impedir.
--
-- **El mismo defecto estaba en DOS sitios**, y se corrigen juntos porque son una
-- sola idea: `validate_supplier_journal_provenance` (sobre `journal_entries`) y
-- `derive_journal_line_counterparty` (sobre `journal_lines`). El tercer consumidor
-- del resolutor, `sync_supplier_journal_counterparties`, ya trataba bien el nulo:
-- sólo escribe la contraparte cuando existe. Se comprobó que no hay un cuarto.

create or replace function public.journal_supplier_source_exists_in_tenant(
  p_tenant_id uuid,
  p_source_document_type text,
  p_source_document_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_exists boolean := false;
begin
  if p_tenant_id is null or p_source_document_id is null then
    return false;
  end if;

  if p_source_document_type = 'purchase_invoice' then
    select exists (
      select 1 from public.purchase_invoices document
      where document.tenant_id = p_tenant_id
        and document.id = p_source_document_id
    ) into v_exists;
  elsif p_source_document_type = 'expense' then
    select exists (
      select 1 from public.expenses document
      where document.tenant_id = p_tenant_id
        and document.id = p_source_document_id
    ) into v_exists;
  elsif p_source_document_type = 'purchase_payment' then
    select exists (
      select 1 from public.purchase_payments document
      where document.tenant_id = p_tenant_id
        and document.id = p_source_document_id
    ) into v_exists;
  elsif p_source_document_type = 'expense_payment' then
    select exists (
      select 1 from public.expense_payments document
      where document.tenant_id = p_tenant_id
        and document.id = p_source_document_id
    ) into v_exists;
  elsif p_source_document_type = 'purchase_credit_note' then
    select exists (
      select 1 from public.purchase_credit_notes document
      where document.tenant_id = p_tenant_id
        and document.id = p_source_document_id
    ) into v_exists;
  elsif p_source_document_type = 'purchase_supplier_refund' then
    select exists (
      select 1 from public.purchase_supplier_refunds document
      where document.tenant_id = p_tenant_id
        and document.id = p_source_document_id
    ) into v_exists;
  end if;

  return coalesce(v_exists, false);
end;
$$;

revoke all on function public.journal_supplier_source_exists_in_tenant(
  uuid, text, uuid
) from public, anon, authenticated, service_role;

create or replace function public.validate_supplier_journal_provenance()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_party_id uuid;
  v_is_supplier_source boolean := new.source_document_type in (
    'purchase_invoice', 'expense', 'purchase_payment', 'expense_payment',
    'purchase_credit_note', 'purchase_supplier_refund'
  );
begin
  v_party_id := public.resolve_supplier_party_for_journal_source(
    new.tenant_id,
    new.source_document_type,
    new.source_document_id,
    new.source_module,
    new.source_reference
  );

  -- Sin parte hay que distinguir «no existe el documento» de «el documento no
  -- nombra a ningún proveedor». Lo primero es la violación que este guard
  -- existe para impedir; lo segundo es un sueldo, o cualquiera de los gastos
  -- que se registran sin proveedor.
  if v_is_supplier_source
     and v_party_id is null
     and not public.journal_supplier_source_exists_in_tenant(
       new.tenant_id,
       new.source_document_type,
       new.source_document_id
     ) then
    raise exception 'Canonical journal source is missing or outside tenant'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
     and row(
       old.tenant_id,
       old.source_document_type,
       old.source_document_id,
       old.source_module,
       old.source_reference
     ) is distinct from row(
       new.tenant_id,
       new.source_document_type,
       new.source_document_id,
       new.source_module,
       new.source_reference
     )
     and exists (
       select 1
       from public.journal_lines line
       where line.tenant_id = old.tenant_id
         and line.entry_id = old.id
         and line.counterparty_party_id is not null
         and line.counterparty_party_id is distinct from v_party_id
     ) then
    raise exception 'Journal provenance change contradicts existing counterparty lines'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_supplier_journal_provenance()
  from public, anon, authenticated, service_role;


-- Segundo sitio, mismo criterio: la línea del asiento tampoco puede exigir una
-- contraparte de proveedor a un documento que legítimamente no tiene ninguno.
create or replace function public.derive_journal_line_counterparty()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_entry public.journal_entries%rowtype;
  v_party_id uuid;
begin
  if new.entry_id is null then
    return new;
  end if;

  select entry.*
  into v_entry
  from public.journal_entries entry
  where entry.id = new.entry_id
    and entry.tenant_id = new.tenant_id;

  if not found then
    return new;
  end if;

  v_party_id := public.resolve_supplier_party_for_journal_source(
    new.tenant_id,
    v_entry.source_document_type,
    v_entry.source_document_id,
    v_entry.source_module,
    v_entry.source_reference
  );

  if v_entry.source_document_type in (
    'purchase_invoice', 'expense', 'purchase_payment', 'expense_payment',
    'purchase_credit_note', 'purchase_supplier_refund'
  ) and v_party_id is null
    and not public.journal_supplier_source_exists_in_tenant(
      new.tenant_id,
      v_entry.source_document_type,
      v_entry.source_document_id
    ) then
    raise exception 'Canonical journal source cannot resolve supplier counterparty'
      using errcode = '23514';
  end if;

  if v_party_id is not null then
    if new.counterparty_party_id is not null
       and new.counterparty_party_id is distinct from v_party_id then
      raise exception 'Journal line counterparty contradicts canonical source'
        using errcode = '23514';
    end if;

    if new.counterparty_context is not null
       and new.counterparty_context <> 'supplier' then
      raise exception 'Journal line counterparty context contradicts canonical source'
        using errcode = '23514';
    end if;

    new.counterparty_party_id := v_party_id;
    new.counterparty_context := 'supplier';
  end if;

  return new;
end;
$$;

revoke all on function public.derive_journal_line_counterparty()
  from public, anon, authenticated, service_role;
