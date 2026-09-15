begin;

select no_plan();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

-- -------------------------------------------------------------------------
-- Un gasto sin proveedor es legítimo, y confirmar una nómina depende de eso.
--
-- Regresión medida en producción el 2026-08-10: `Confirmar semana` moría con
-- `Canonical journal source is missing or outside tenant` (23514) porque los
-- guards de procedencia trataban `source_document_type = 'expense'` como
-- documento de proveedor SIEMPRE. Un sueldo no se le compra a nadie —y 79 de
-- los 137 gastos del taller tampoco tienen proveedor—, así que toda
-- confirmación de nómina se revertía entera.
--
-- El guard sigue en pie: lo que dejó de hacer es confundir «el documento no
-- existe / es de otro tenant» con «el documento no nombra a ningún proveedor».
-- -------------------------------------------------------------------------

select has_function(
  'public',
  'journal_supplier_source_state',
  array['uuid', 'text', 'uuid'],
  'el estado del documento fuente es explícito, no un booleano ambiguo'
);

select is(
  public.journal_supplier_source_state(
    gen_random_uuid(), 'expense', gen_random_uuid()
  ),
  'missing',
  'un gasto inexistente es «missing», no «sin proveedor»'
);

select is(
  public.journal_supplier_source_exists_in_tenant(
    gen_random_uuid(), 'expense', gen_random_uuid()
  ),
  false,
  'un gasto inexistente no existe en ningún tenant'
);

select is(
  public.journal_supplier_source_exists_in_tenant(null, 'expense', null),
  false,
  'sin tenant ni documento no hay procedencia que afirmar'
);

-- Los dos guards conservan el mensaje y el errcode originales: la violación
-- real se sigue rechazando igual, y su texto es parte del contrato.
select ok(
  (
    select prosrc like '%Canonical journal source is missing or outside tenant%'
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'validate_supplier_journal_provenance'
  ),
  'la violación de procedencia conserva su mensaje'
);

select ok(
  (
    select prosrc like '%journal_supplier_source_state%'
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'validate_supplier_journal_provenance'
  ),
  'el asiento distingue los tres estados del documento fuente'
);

select ok(
  (
    select prosrc like '%journal_supplier_source_state%'
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'derive_journal_line_counterparty'
  ),
  'la línea del asiento hace la misma distinción'
);

-- La dimensión tipada de contraparte que el propio refactor publicó admite
-- siete contextos, no sólo proveedor: exigir un proveedor a todo gasto
-- contradecía ese diseño.
select ok(
  (
    select pg_get_constraintdef(c.oid) like '%landlord%'
    from pg_constraint c
    where c.conname = 'journal_lines_counterparty_context_check'
  ),
  'la contraparte tipada admite orígenes que no son proveedor'
);

-- -------------------------------------------------------------------------
-- El comportamiento, con una sesión autenticada real.
-- -------------------------------------------------------------------------

insert into public.tenants (id, shop_name)
values ('98510000-0000-4000-8000-000000000001', 'Journal Provenance Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '98510000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated',
  'journal-provenance@example.invalid', '', now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '98510000-0000-4000-8000-000000000001'),
  now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98510000-0000-4000-8000-000000000099',
  '98510000-0000-4000-8000-000000000001',
  'admin'
);

-- Y un gasto del MISMO tenant que nombra un proveedor de OTRO tenant: la
-- posibilidad que abrió la primera corrección y que ésta cierra.
insert into public.tenants (id, shop_name)
values ('98510000-0000-4000-8000-000000000002', 'Tenant vecino');

insert into public.external_parties (id, tenant_id, display_name)
values (
  '98510000-0000-4000-8000-000000000040',
  '98510000-0000-4000-8000-000000000002',
  'Proveedor ajeno'
);

insert into public.suppliers (id, tenant_id, name, party_id)
values (
  '98510000-0000-4000-8000-000000000040',
  '98510000-0000-4000-8000-000000000002',
  'Proveedor ajeno',
  '98510000-0000-4000-8000-000000000040'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98510000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98510000-0000-4000-8000-000000000099',
  true
);

-- Un gasto SIN proveedor: exactamente el que crea una nómina al confirmarse.
insert into public.expenses (
  id, tenant_id, expense_number, document_type, issue_date,
  posting_status, payment_status, subtotal, tax_amount, total_amount
) values (
  '98510000-0000-4000-8000-000000000030',
  '98510000-0000-4000-8000-000000000001',
  'GTO-PROV-001', 'ticket', now(), 'posted', 'pending', 1000, 0, 1000
);

insert into public.expenses (
  id, tenant_id, supplier_id, expense_number, document_type, issue_date,
  posting_status, payment_status, subtotal, tax_amount, total_amount
) values (
  '98510000-0000-4000-8000-000000000031',
  '98510000-0000-4000-8000-000000000001',
  '98510000-0000-4000-8000-000000000040',
  'GTO-PROV-002', 'ticket', now(), 'posted', 'pending', 1000, 0, 1000
);

select is(
  public.journal_supplier_source_state(
    '98510000-0000-4000-8000-000000000001',
    'expense',
    '98510000-0000-4000-8000-000000000030'
  ),
  'supplierless',
  'un gasto sin proveedor es «supplierless»'
);

select is(
  public.journal_supplier_source_state(
    '98510000-0000-4000-8000-000000000001',
    'expense',
    '98510000-0000-4000-8000-000000000031'
  ),
  'supplier_named',
  'un gasto que nombra proveedor NO es «sin proveedor», aunque no resuelva'
);

select is(
  public.journal_supplier_source_state(
    '98510000-0000-4000-8000-000000000001',
    'expense',
    '98510000-0000-4000-8000-000000000099'
  ),
  'missing',
  'un gasto que no existe en el tenant sigue siendo «missing»'
);

select is(
  public.resolve_supplier_party_for_journal_source(
    '98510000-0000-4000-8000-000000000001',
    'expense',
    '98510000-0000-4000-8000-000000000030',
    null, null
  ),
  null,
  'el gasto sin proveedor no resuelve ninguna parte, como corresponde'
);

-- Las escrituras que siguen se hacen **como `authenticated`**, no como
-- superusuario: sin `set local role` el motor salta la RLS y el test no prueba
-- lo que la app hace de verdad (revisión de Codex, 2026-08-11).
set local role authenticated;

select lives_ok(
  $lives$
    insert into public.journal_entries (
      tenant_id, entry_number, entry_date, description, type,
      source_document_type, source_document_id
    ) values (
      '98510000-0000-4000-8000-000000000001',
      'AS-PROV-001', now(), 'Asiento de sueldo', 'expense',
      'expense', '98510000-0000-4000-8000-000000000030'
    )
  $lives$,
  'un gasto sin proveedor acepta su asiento contable'
);

select lives_ok(
  $lives$
    insert into public.journal_lines (
      tenant_id, entry_id, account_id, account_code, account_name, debit_amount, credit_amount
    )
    select
      '98510000-0000-4000-8000-000000000001',
      entry.id,
      account.id, '6101-99', 'Salario de prueba', 1000, 0
    from public.journal_entries entry
    cross join lateral (
      select id from public.accounts
      where tenant_id = '98510000-0000-4000-8000-000000000001'
      limit 1
    ) account
    where entry.entry_number = 'AS-PROV-001'
      and entry.tenant_id = '98510000-0000-4000-8000-000000000001'
  $lives$,
  'y sus líneas quedan con contraparte nula, sin inventar un proveedor'
);

select throws_ok(
  $throws$
    insert into public.journal_entries (
      tenant_id, entry_number, entry_date, description, type,
      source_document_type, source_document_id
    ) values (
      '98510000-0000-4000-8000-000000000001',
      'AS-PROV-002', now(), 'Asiento sin documento', 'expense',
      'expense', '98510000-0000-4000-8000-000000000099'
    )
  $throws$,
  '23514',
  'Canonical journal source is missing or outside tenant',
  'un documento fuente inexistente se sigue rechazando'
);

select throws_ok(
  $throws$
    insert into public.journal_entries (
      tenant_id, entry_number, entry_date, description, type,
      source_document_type, source_document_id
    ) values (
      '98510000-0000-4000-8000-000000000001',
      'AS-PROV-003', now(), 'Asiento con proveedor ajeno', 'expense',
      'expense', '98510000-0000-4000-8000-000000000031'
    )
  $throws$,
  '23514',
  'Canonical journal source is missing or outside tenant',
  'un proveedor de otro tenant NO se acepta como «sin proveedor»'
);

reset role;

-- -------------------------------------------------------------------------
-- Matriz de los seis tipos: quién puede no tener proveedor y quién no.
--
-- Un gasto y su pago pueden no tenerlo —un sueldo, un arriendo—. Una factura
-- de compra, su pago, su nota de crédito y su reembolso existen PORQUE hay un
-- proveedor: ahí la ausencia es procedencia rota, no un caso de negocio.
-- (P1 encontrado por la re-auditoría de Codex, 2026-08-11.)
-- -------------------------------------------------------------------------

select is(
  public.journal_source_may_be_supplierless('expense'), true,
  'un gasto puede no tener proveedor'
);
select is(
  public.journal_source_may_be_supplierless('expense_payment'), true,
  'el pago de un gasto hereda esa verdad'
);
select is(
  public.journal_source_may_be_supplierless('purchase_invoice'), false,
  'una factura de compra NO puede quedarse sin proveedor'
);
select is(
  public.journal_source_may_be_supplierless('purchase_payment'), false,
  'ni el pago de una compra'
);
select is(
  public.journal_source_may_be_supplierless('purchase_credit_note'), false,
  'ni una nota de crédito de compra'
);
select is(
  public.journal_source_may_be_supplierless('purchase_supplier_refund'), false,
  'ni un reembolso de proveedor'
);

-- Una compra REAL sin proveedor, para probar el rechazo con datos, no sólo
-- con el predicado.
insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_id, subtotal, total, balance
) values (
  '98510000-0000-4000-8000-000000000060',
  '98510000-0000-4000-8000-000000000001',
  'FC-PROV-001', null, 1000, 1000, 1000
);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id
)
select
  '98510000-0000-4000-8000-000000000070',
  '98510000-0000-4000-8000-000000000001',
  'efectivo-test', 'Efectivo prueba', account.id
from (
  select id from public.accounts
  where tenant_id = '98510000-0000-4000-8000-000000000001' limit 1
) account;

-- Registrar el pago dispara la creación de su asiento, y ese asiento ya lo
-- rechaza el guard: la cadena entera de una compra sin proveedor queda cerrada,
-- que es justo lo que se busca. Para poder AFIRMARLO sobre la fila, el pago se
-- siembra con el guard desactivado —evidencia heredada— y se reactiva enseguida.
alter table public.journal_entries disable trigger trg_validate_supplier_journal_provenance;
alter table public.journal_lines disable trigger trg_derive_journal_line_counterparty;

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, date
) values (
  '98510000-0000-4000-8000-000000000061',
  '98510000-0000-4000-8000-000000000001',
  '98510000-0000-4000-8000-000000000060',
  '98510000-0000-4000-8000-000000000070',
  1000, now()
);

alter table public.journal_lines enable trigger trg_derive_journal_line_counterparty;
alter table public.journal_entries enable trigger trg_validate_supplier_journal_provenance;

select is(
  public.journal_supplier_source_state(
    '98510000-0000-4000-8000-000000000001',
    'purchase_invoice',
    '98510000-0000-4000-8000-000000000060'
  ),
  'supplierless',
  'el estado describe el hecho: la factura no nombra proveedor'
);

select throws_ok(
  $throws$
    insert into public.journal_entries (
      tenant_id, entry_number, entry_date, description, type,
      source_document_type, source_document_id
    ) values (
      '98510000-0000-4000-8000-000000000001',
      'AS-PROV-010', now(), 'Compra sin proveedor', 'expense',
      'purchase_invoice', '98510000-0000-4000-8000-000000000060'
    )
  $throws$,
  '23514',
  'Canonical journal source is missing or outside tenant',
  'pero una factura de compra sin proveedor se RECHAZA'
);

select throws_ok(
  $throws$
    insert into public.journal_entries (
      tenant_id, entry_number, entry_date, description, type,
      source_document_type, source_document_id
    ) values (
      '98510000-0000-4000-8000-000000000001',
      'AS-PROV-011', now(), 'Pago de compra sin proveedor', 'expense',
      'purchase_payment', '98510000-0000-4000-8000-000000000061'
    )
  $throws$,
  '23514',
  'Canonical journal source is missing or outside tenant',
  'y el pago de esa compra también'
);

-- El pago de un gasto SÍ puede ser supplierless: mismo camino que el sueldo.
insert into public.expense_payments (
  id, tenant_id, expense_id
) values (
  '98510000-0000-4000-8000-000000000062',
  '98510000-0000-4000-8000-000000000001',
  '98510000-0000-4000-8000-000000000030'
);

select lives_ok(
  $lives$
    insert into public.journal_entries (
      tenant_id, entry_number, entry_date, description, type,
      source_document_type, source_document_id
    ) values (
      '98510000-0000-4000-8000-000000000001',
      'AS-PROV-012', now(), 'Pago de sueldo', 'expense',
      'expense_payment', '98510000-0000-4000-8000-000000000062'
    )
  $lives$,
  'el pago de un gasto sin proveedor sí acepta su asiento'
);

-- -------------------------------------------------------------------------
-- El trigger de LÍNEA rechaza por su cuenta.
--
-- Un asiento de compra sin proveedor ya no se puede insertar, así que para
-- alcanzar el trigger de línea se simula evidencia heredada: se desactiva el
-- guard del asiento, se inserta la fila imposible, y se vuelve a activar. Lo
-- que se prueba es que la línea NO se apoya en que el asiento haya pasado.
-- -------------------------------------------------------------------------
alter table public.journal_entries disable trigger trg_validate_supplier_journal_provenance;

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_document_type, source_document_id
) values (
  '98510000-0000-4000-8000-000000000080',
  '98510000-0000-4000-8000-000000000001',
  'AS-PROV-013', now(), 'Asiento heredado', 'expense',
  'purchase_invoice', '98510000-0000-4000-8000-000000000060'
);

alter table public.journal_entries enable trigger trg_validate_supplier_journal_provenance;

select throws_ok(
  $throws$
    insert into public.journal_lines (
      tenant_id, entry_id, account_id, account_code, account_name,
      debit_amount, credit_amount
    )
    select
      '98510000-0000-4000-8000-000000000001',
      '98510000-0000-4000-8000-000000000080',
      account.id, '6101-99', 'Salario de prueba', 1000, 0
    from (
      select id from public.accounts
      where tenant_id = '98510000-0000-4000-8000-000000000001' limit 1
    ) account
  $throws$,
  '23514',
  'Canonical journal source cannot resolve supplier counterparty',
  'la línea rechaza por su cuenta, sin apoyarse en el guard del asiento'
);

-- -------------------------------------------------------------------------
-- La línea del sueldo se insertó DE VERDAD, y quedó sin contraparte.
-- -------------------------------------------------------------------------
select is(
  (
    select count(*)::int
    from public.journal_lines line
    join public.journal_entries entry on entry.id = line.entry_id
    where entry.entry_number = 'AS-PROV-001'
      and entry.tenant_id = '98510000-0000-4000-8000-000000000001'
  ),
  1,
  'la línea del asiento de sueldo existe en la tabla, no sólo «no lanzó»'
);

select is(
  (
    select count(*)::int
    from public.journal_lines line
    join public.journal_entries entry on entry.id = line.entry_id
    where entry.entry_number = 'AS-PROV-001'
      and entry.tenant_id = '98510000-0000-4000-8000-000000000001'
      and line.counterparty_party_id is null
      and line.counterparty_context is null
  ),
  1,
  'y quedó con party y context nulos: no se inventó ningún proveedor'
);


select * from finish();
rollback;
