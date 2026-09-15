begin;

-- «Sin proveedor» y «con un proveedor que no resuelve» no son lo mismo.
--
-- **Cierra el P1 que la revisión de Codex encontró en `20260810210000`
-- (2026-08-11).** Aquella corrección distinguía dos estados —el documento no
-- existe, o el documento existe— y permitía el asiento en el segundo. Pero
-- «existe» no prueba que su cadena de proveedor sea coherente: un gasto del
-- tenant A cuyo `supplier_id` apunte a un proveedor del tenant B hace que el
-- resolutor canónico devuelva `null`, el helper confirme que el gasto existe, y
-- el guard lo acepte **como si el gasto no tuviera proveedor**. Eso convierte
-- una violación de aislamiento en un asiento válido con contraparte nula.
--
-- La causa es que `expenses.supplier_id` y `purchase_invoices.supplier_id`
-- referencian `suppliers(id)` a secas, no `(tenant_id, supplier_id)`, así que la
-- base no impide por sí sola que apunten fuera del tenant. Las FKs compuestas
-- son la corrección de fondo y van aparte; este guard deja de depender de que
-- existan.
--
-- Producción tiene **cero** casos hoy, comprobado antes de aplicar: esto cierra
-- una posibilidad, no repara un daño.
--
-- Los tres estados quedan explícitos:
--
--   `missing`        el documento no existe en el tenant, o su cadena se corta
--                    fuera de él                              → 23514
--   `supplier_named` el documento nombra un proveedor que no resuelve dentro
--                    del tenant                               → 23514
--   `supplierless`   el documento existe y no nombra proveedor → se permite
--
-- Sólo el tercero es el sueldo, y los otros gastos legítimos sin proveedor.

create or replace function public.journal_supplier_source_state(
  p_tenant_id uuid,
  p_source_document_type text,
  p_source_document_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_found boolean := false;
  v_supplier_id uuid;
begin
  if p_tenant_id is null or p_source_document_id is null then
    return 'missing';
  end if;

  -- Cada rama devuelve DOS hechos: si la cadena se pudo recorrer entera dentro
  -- del tenant, y el `supplier_id` que nombra (que puede ser nulo). Para los
  -- documentos encadenados —un pago cuelga de su factura— una cadena que se
  -- corta fuera del tenant es `missing`, no «sin proveedor».
  if p_source_document_type = 'purchase_invoice' then
    select true, document.supplier_id into v_found, v_supplier_id
    from public.purchase_invoices document
    where document.tenant_id = p_tenant_id
      and document.id = p_source_document_id;
  elsif p_source_document_type = 'expense' then
    select true, document.supplier_id into v_found, v_supplier_id
    from public.expenses document
    where document.tenant_id = p_tenant_id
      and document.id = p_source_document_id;
  elsif p_source_document_type = 'purchase_payment' then
    select true, invoice.supplier_id into v_found, v_supplier_id
    from public.purchase_payments document
    join public.purchase_invoices invoice
      on invoice.tenant_id = document.tenant_id
     and invoice.id = document.invoice_id
    where document.tenant_id = p_tenant_id
      and document.id = p_source_document_id;
  elsif p_source_document_type = 'expense_payment' then
    select true, expense.supplier_id into v_found, v_supplier_id
    from public.expense_payments document
    join public.expenses expense
      on expense.tenant_id = document.tenant_id
     and expense.id = document.expense_id
    where document.tenant_id = p_tenant_id
      and document.id = p_source_document_id;
  elsif p_source_document_type = 'purchase_credit_note' then
    select true, invoice.supplier_id into v_found, v_supplier_id
    from public.purchase_credit_notes document
    join public.purchase_invoices invoice
      on invoice.tenant_id = document.tenant_id
     and invoice.id = document.purchase_invoice_id
    where document.tenant_id = p_tenant_id
      and document.id = p_source_document_id;
  elsif p_source_document_type = 'purchase_supplier_refund' then
    select true, invoice.supplier_id into v_found, v_supplier_id
    from public.purchase_supplier_refunds document
    join public.purchase_invoices invoice
      on invoice.tenant_id = document.tenant_id
     and invoice.id = document.purchase_invoice_id
    where document.tenant_id = p_tenant_id
      and document.id = p_source_document_id;
  end if;

  if not coalesce(v_found, false) then
    return 'missing';
  end if;
  if v_supplier_id is not null then
    return 'supplier_named';
  end if;
  return 'supplierless';
end;
$$;

revoke all on function public.journal_supplier_source_state(uuid, text, uuid)
  from public, anon, authenticated, service_role;

-- El helper anterior queda expresado sobre el nuevo estado, para que exista una
-- sola definición de «existe» y ningún consumidor futuro herede la ambigüedad.
create or replace function public.journal_supplier_source_exists_in_tenant(
  p_tenant_id uuid,
  p_source_document_type text,
  p_source_document_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select public.journal_supplier_source_state(
    p_tenant_id, p_source_document_type, p_source_document_id
  ) <> 'missing';
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

  -- Sólo un documento que existe y NO nombra proveedor puede llevar contraparte
  -- nula. Un documento inexistente, y uno que nombra un proveedor que no
  -- resuelve dentro del tenant, siguen siendo la violación de siempre.
  if v_is_supplier_source
     and v_party_id is null
     and public.journal_supplier_source_state(
       new.tenant_id,
       new.source_document_type,
       new.source_document_id
     ) <> 'supplierless' then
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
    and public.journal_supplier_source_state(
      new.tenant_id,
      v_entry.source_document_type,
      v_entry.source_document_id
    ) <> 'supplierless' then
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

commit;
