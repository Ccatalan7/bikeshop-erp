begin;

-- Deployment status: reviewed forward migration; production apply is allowed
-- only after the exact-SHA focused gates and read-only preflight pass.
-- Verification owner: journal provenance + expense journal RPC ACL suites.

-- Sólo un gasto puede no tener proveedor. Una compra, siempre.
--
-- **Cierra el P1 que la re-auditoría de Codex encontró en `20260811030000`
-- (2026-08-11).** Aquella migración distingue bien los tres estados del
-- documento fuente, pero aplica la excepción `supplierless` a los **seis**
-- tipos. Eso deja pasar sin proveedor a `purchase_invoice`,
-- `purchase_payment`, `purchase_credit_note` y `purchase_supplier_refund`, y
-- esos cuatro **son** documentos de compra: existen porque hay un proveedor
-- detrás. Un asiento de compra sin contraparte no es un caso legítimo, es una
-- procedencia rota.
--
-- La excepción se estrecha a `expense` y `expense_payment`, que son los dos
-- únicos donde la ausencia de proveedor es un hecho normal del negocio: el
-- sueldo que crea la nómina, y su pago. Para los cuatro `purchase_*`, un
-- `v_party_id` nulo vuelve a ser `23514` aunque la fila exista.
--
-- `journal_supplier_source_state` no cambia: describe el documento y ésa sigue
-- siendo su única responsabilidad. Quién puede acogerse a `supplierless` es una
-- decisión del guard, y se declara aparte para que ambos guards la compartan y
-- ninguno pueda desviarse del otro en silencio.
--
-- `20260811030000` queda congelada byte-idéntica: está aplicada y registrada en
-- producción (SHA-256 4066472bd435fa4531fb7c5119df1aa522c2eef540902a6745567351aa75f2c9).
-- Esto es un forward atómico, no una reescritura de historia.

-- `20260802120000_add_audited_payroll_settlement_reversals.sql` recreated the
-- traced expense-payment wrapper and accidentally restored direct EXECUTE to
-- `authenticated`. The table trigger already calls it through its
-- SECURITY DEFINER owner; no Flutter consumer calls this RPC directly, and the
-- canonical tenant-scope suites require employee calls to fail at the ACL.
-- Restore the previously frozen service-only command boundary before changing
-- the provenance guards.
revoke all on function public.create_expense_payment_journal_entry(uuid)
  from public, anon, authenticated;
grant execute on function public.create_expense_payment_journal_entry(uuid)
  to service_role;

create or replace function public.journal_source_may_be_supplierless(
  p_source_document_type text
)
returns boolean
language sql
immutable
as $$
  -- Un gasto puede no tener proveedor —un sueldo, un arriendo, un impuesto— y
  -- su pago hereda esa misma verdad. Una factura de compra, su pago, su nota de
  -- crédito y su reembolso existen porque hay un proveedor: ahí la ausencia es
  -- una procedencia rota, no un caso de negocio.
  select p_source_document_type in ('expense', 'expense_payment');
$$;

revoke all on function public.journal_source_may_be_supplierless(text)
  from public, anon, authenticated, service_role;

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

  -- La contraparte nula sólo se acepta cuando el tipo admite no tener
  -- proveedor Y el documento existe sin nombrarlo. Cualquier otra combinación
  -- —documento inexistente, proveedor que no resuelve en el tenant, o un
  -- documento de compra sin proveedor— es la violación de siempre.
  if v_is_supplier_source
     and v_party_id is null
     and not (
       public.journal_source_may_be_supplierless(new.source_document_type)
       and public.journal_supplier_source_state(
         new.tenant_id,
         new.source_document_type,
         new.source_document_id
       ) = 'supplierless'
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
    and not (
      public.journal_source_may_be_supplierless(v_entry.source_document_type)
      and public.journal_supplier_source_state(
        new.tenant_id,
        v_entry.source_document_type,
        v_entry.source_document_id
      ) = 'supplierless'
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

commit;
