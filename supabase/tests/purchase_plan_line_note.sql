begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- La nota libre de una línea del plan.
--
-- Lo que estas pruebas defienden:
--   · limpiar es explícito y no deja una cadena en blanco viviendo en la fila;
--   · un no-op **consume** su clave, o el replay deja de significar algo;
--   · la clave de otro cambio no se reutiliza en silencio;
--   · sólo una línea activa de un plan borrador acepta nota;
--   · la versión del plan gobierna, y sólo sube cuando algo cambió.

select has_column(
  'public', 'purchase_plan_lines', 'note',
  'a plan line can carry the operator note the contract asks for'
);
select has_function(
  'public', 'set_purchase_plan_line_note_v1',
  array['uuid', 'bigint', 'uuid', 'text', 'text'],
  'setting and clearing the note is one replay-safe command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.set_purchase_plan_line_note_v1(uuid,bigint,uuid,text,text)',
    'execute'
  ),
  'the operator can run it'
);

-- ───────────────────────────── datos de prueba ─────────────────────────────
insert into public.tenants(id, shop_name, currency, timezone) values (
  '99b10000-0000-4000-8000-000000000001',
  'Plan Note Tenant', 'CLP', 'America/Santiago'
);
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99b10000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'plan-note@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99b10000-0000-4000-8000-000000000099',
  '99b10000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99b10000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99b10000-0000-4000-8000-000000000099',
  true
);

insert into public.products(
  id, tenant_id, name, sku, is_active, price
) values (
  '99b10000-0000-4000-8000-000000000031',
  '99b10000-0000-4000-8000-000000000001',
  'Cámara 29 Schrader', 'CAM-29-SCH', true, 9990
);
insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values (
  '99b10000-0000-4000-8000-000000000041',
  '99b10000-0000-4000-8000-000000000001',
  'ad_hoc', 'Cámaras 29 Schrader',
  '99b10000-0000-4000-8000-000000000031', 4, 'unit',
  'confirmed', 'open', 'not_applicable', 1
);
insert into public.purchase_plans(
  id, tenant_id, title, state, objective_profile, version, created_by
) values (
  '99b10000-0000-4000-8000-000000000051',
  '99b10000-0000-4000-8000-000000000001',
  'Plan de compra 2026-08-19', 'draft', 'balanced', 1,
  '99b10000-0000-4000-8000-000000000099'
);
insert into public.purchase_plan_lines(
  id, tenant_id, plan_id, source_need_id, candidate_id, product_id,
  supplier_name, quantity, unit, currency_code, evidence_snapshot, state,
  created_by
) values (
  '99b10000-0000-4000-8000-000000000061',
  '99b10000-0000-4000-8000-000000000001',
  '99b10000-0000-4000-8000-000000000051',
  '99b10000-0000-4000-8000-000000000041',
  '99b10000-0000-4000-8000-000000000071',
  '99b10000-0000-4000-8000-000000000031',
  'TeknoBike', 4, 'unit', 'CLP', '{}'::jsonb, 'active',
  '99b10000-0000-4000-8000-000000000099'
);

-- ───────────────────────── escribir, leer, limpiar ─────────────────────────
select lives_ok(
  $$select public.set_purchase_plan_line_note_v1(
      '99b10000-0000-4000-8000-000000000051', 1,
      '99b10000-0000-4000-8000-000000000061',
      '  Se eligió por plazo, no por precio.  ',
      'note-1'
    )$$,
  'the operator can say why this candidate and not another'
);
select is(
  (select note from public.purchase_plan_lines
   where id = '99b10000-0000-4000-8000-000000000061'),
  'Se eligió por plazo, no por precio.',
  'the note is stored trimmed, not as the operator happened to type it'
);
select is(
  (select version from public.purchase_plans
   where id = '99b10000-0000-4000-8000-000000000051')::bigint,
  2::bigint,
  'a real change moves the plan version'
);

-- Un no-op consume su clave y NO mueve la versión.
select is(
  (public.set_purchase_plan_line_note_v1(
    '99b10000-0000-4000-8000-000000000051', 2,
    '99b10000-0000-4000-8000-000000000061',
    'Se eligió por plazo, no por precio.',
    'note-2-noop'
  ) ->> 'changed')::boolean,
  false,
  'writing the same note changes nothing and says so'
);
select is(
  (select version from public.purchase_plans
   where id = '99b10000-0000-4000-8000-000000000051')::bigint,
  2::bigint,
  'and a no-op never moves the version'
);
select is(
  (select count(*)::integer from public.purchase_plan_events
   where operation_key = 'note-2-noop'),
  1,
  'but it does leave its receipt: the key is consumed, not left free'
);

-- El replay devuelve lo mismo y no escribe otra vez.
select is(
  (public.set_purchase_plan_line_note_v1(
    '99b10000-0000-4000-8000-000000000051', 2,
    '99b10000-0000-4000-8000-000000000061',
    'Se eligió por plazo, no por precio.',
    'note-2-noop'
  ) ->> 'replay')::boolean,
  true,
  'the same key replays instead of writing twice'
);
select is(
  (select count(*)::integer from public.purchase_plan_events
   where operation_key = 'note-2-noop'),
  1,
  'and the replay adds no second receipt'
);

-- Una clave usada para otra nota se rechaza en vez de pisar la anterior.
select throws_ok(
  $$select public.set_purchase_plan_line_note_v1(
      '99b10000-0000-4000-8000-000000000051', 2,
      '99b10000-0000-4000-8000-000000000061',
      'Otra razón distinta',
      'note-1'
    )$$,
  '23505',
  'La clave de operación pertenece a otro cambio del plan.',
  'a key never silently covers a different note'
);

-- Limpiar es explícito, y deja NULL, no una cadena en blanco.
select is(
  (public.set_purchase_plan_line_note_v1(
    '99b10000-0000-4000-8000-000000000051', 2,
    '99b10000-0000-4000-8000-000000000061',
    '   ',
    'note-3-clear'
  ) ->> 'changed')::boolean,
  true,
  'clearing is a real change'
);
select ok(
  (select note is null from public.purchase_plan_lines
   where id = '99b10000-0000-4000-8000-000000000061'),
  'and it stores NULL, never a blank string'
);

-- La versión del plan gobierna.
select throws_ok(
  $$select public.set_purchase_plan_line_note_v1(
      '99b10000-0000-4000-8000-000000000051', 1,
      '99b10000-0000-4000-8000-000000000061',
      'Con la versión vieja',
      'note-4-stale'
    )$$,
  '40001',
  'El plan cambió; vuelve a cargarlo antes de guardar.',
  'a stale plan version is refused, not merged'
);

-- Una línea retirada ya no acepta nota.
update public.purchase_plan_lines
set state = 'removed'
where id = '99b10000-0000-4000-8000-000000000061';
select throws_ok(
  $$select public.set_purchase_plan_line_note_v1(
      '99b10000-0000-4000-8000-000000000051', 3,
      '99b10000-0000-4000-8000-000000000061',
      'Sobre una línea retirada',
      'note-5-removed'
    )$$,
  '55000',
  'Sólo una línea activa puede llevar nota.',
  'a removed line is not a place to leave a note'
);

-- Y la columna rechaza una nota en blanco escrita por fuera del comando.
update public.purchase_plan_lines
set state = 'active'
where id = '99b10000-0000-4000-8000-000000000061';
select throws_ok(
  $$update public.purchase_plan_lines
      set note = '   '
      where id = '99b10000-0000-4000-8000-000000000061'$$,
  '23514',
  null,
  'the column itself refuses a blank note, not only the command'
);

select finish();
rollback;
