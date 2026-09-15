begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- El nombre del producto como evidencia — y el servidor como el que juzga.
--
-- Lo que estas pruebas defienden, en una frase: **que la cita exista en el
-- texto no basta**. Una salida adversarial que cite «METALICA» y la normalice
-- como «Orgánico» tiene que morir en el servidor, no en el cliente, porque el
-- cliente es justamente la parte que podría estar equivocada.
--
-- Y las tres garantías que la hacen usable:
--   · la procedencia es un token propio, así que ningún consumidor la acepta
--     por descuido;
--   · la evidencia queda atada al texto que se leyó y caduca sola si cambia;
--   · una duda no escribe nada, y la fila sigue sin verificar.

select has_function(
  'public', 'spec_reading_rejection_internal_v1',
  array['uuid', 'jsonb', 'text'],
  'un solo dueño decide si una cita sostiene un valor'
);
select has_function(
  'public', 'record_product_spec_reading_v1',
  array['uuid', 'text', 'jsonb', 'text', 'text'],
  'la escritura pasa por el servidor, que comprueba antes de guardar'
);
select has_table('public', 'spec_fact_readings', 'el recibo de la lectura vive');

-- ───────────────────────────── datos de prueba ─────────────────────────────
insert into public.tenants(id, shop_name, currency, timezone) values
  (
    '99d50000-0000-4000-8000-000000000001',
    'Name Reading Tenant', 'CLP', 'America/Santiago'
  ),
  (
    '99d50000-0000-4000-8000-000000000002',
    'Otro Taller', 'CLP', 'America/Santiago'
  );

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99d50000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'name-reading@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99d50000-0000-4000-8000-000000000099',
  '99d50000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true
);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '99d50000-0000-4000-8000-000000000099',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  '99d50000-0000-4000-8000-000000000099', true);

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values (
  '99d50000-0000-4000-8000-000000000011',
  '99d50000-0000-4000-8000-000000000001',
  'Pastillas', 'Frenos / Pastillas', 1, true
);

-- El vocabulario es del taller, no de esta prueba: se declara como ficha.
insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, sort_order
) values
  (
    '99d50000-0000-4000-8000-000000000021',
    '99d50000-0000-4000-8000-000000000001',
    'nr_compound', 'Compuesto', 'single_select', '[]'::jsonb, '{}'::jsonb,
    true, false, true, true, true, 1
  ),
  (
    '99d50000-0000-4000-8000-000000000022',
    '99d50000-0000-4000-8000-000000000001',
    'nr_finned', 'Con Aletas de Calor', 'boolean', '[]'::jsonb, '{}'::jsonb,
    true, false, true, true, true, 2
  ),
  (
    '99d50000-0000-4000-8000-000000000023',
    '99d50000-0000-4000-8000-000000000001',
    'nr_width_mm', 'Ancho', 'number', '[]'::jsonb, '{}'::jsonb,
    true, false, true, true, true, 3
  );

insert into public.spec_definition_values(
  id, tenant_id, spec_definition_id, code, label, sort_order, is_active
) values
  ('99d50000-0000-4000-8000-000000000031',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000021', 'met', 'Metálico', 1, true),
  ('99d50000-0000-4000-8000-000000000032',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000021', 'org', 'Orgánico', 2, true),
  ('99d50000-0000-4000-8000-000000000033',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000021', 'semi', 'Semi-Metálico', 3, true);

insert into public.products(
  id, tenant_id, name, sku, category_id, is_active, price,
  track_stock, stock_quantity
) values
  (
    '99d50000-0000-4000-8000-000000000041',
    '99d50000-0000-4000-8000-000000000001',
    'Pastilla Freno Shimano METALICA J04C Con Disipador', 'NR-1',
    '99d50000-0000-4000-8000-000000000011', true, 9990, true, 5
  ),
  (
    '99d50000-0000-4000-8000-000000000042',
    '99d50000-0000-4000-8000-000000000001',
    'Pastilla Freno SEMI METALICA 48 MM', 'NR-2',
    '99d50000-0000-4000-8000-000000000011', true, 8990, true, 4
  ),
  (
    '99d50000-0000-4000-8000-000000000043',
    '99d50000-0000-4000-8000-000000000001',
    'Pastilla Freno Organica Con Aletas de Calor', 'NR-3',
    '99d50000-0000-4000-8000-000000000011', true, 7990, true, 3
  );

-- ══════════════ 1. La cita tiene que sostener EL valor, no otro ══════════════

-- Éste es el caso adversarial exacto: la cita es real y está en el nombre;
-- lo que el modelo hizo mal fue normalizarla al valor contrario.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000021', '"Orgánico"'::jsonb, 'METALICA'),
  'la cita no dice ese valor',
  'citar METALICA no autoriza a escribir Orgánico'
);

select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000021', '"Metálico"'::jsonb, 'METALICA'),
  null,
  'la misma cita sí sostiene Metálico, aunque flexione distinto'
);

-- «METALICA» cubre entera a `Metálico` y sólo la mitad de `Semi-Metálico`.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000021',
    '"Semi-Metálico"'::jsonb, 'METALICA'),
  'la cita describe mejor otro valor del campo',
  'media etiqueta pierde contra la que la cita cubre entera'
);

-- Y al revés: con «SEMI METALICA» el que gana es el que cubre más.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000021',
    '"Metálico"'::jsonb, 'SEMI METALICA'),
  'la cita describe mejor otro valor del campo',
  'el hermano más específico gana y el genérico se cae'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000021',
    '"Semi-Metálico"'::jsonb, 'SEMI METALICA'),
  null,
  'la lectura específica pasa'
);

-- ═══════════════════ 2. Un booleano sólo se afirma, nunca se niega ══════════

select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000022', 'true'::jsonb, 'Con Disipador'),
  'la cita no dice lo que el campo nombra',
  'el servidor no sabe que un disipador es una aleta y no lo inventa'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000022',
    'true'::jsonb, 'Con Aletas de Calor'),
  null,
  'la afirmación que usa las palabras del propio campo sí entra'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000022',
    'false'::jsonb, 'Pastilla Freno Organica'),
  'la cita no dice lo que el campo nombra',
  'una ausencia no es un cumplimiento: el silencio no niega'
);

-- Pero una negación EXPLÍCITA sí prueba la ausencia. Rechazar todo `false`
-- confundía «no lo menciona» con «dice que no lo trae», que son dos cosas
-- distintas y sólo se distinguen leyendo. Es la misma regla que ya usaban las
-- dos orillas del calce, no una segunda.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000022',
    'false'::jsonb, 'SIN ALETAS DE CALOR'),
  null,
  'decir SIN ALETAS sí prueba que no las trae'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000022',
    'true'::jsonb, 'SIN ALETAS DE CALOR'),
  'la cita dice lo contrario',
  'y la misma cita no puede sostener la afirmación opuesta'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000022',
    'true'::jsonb, 'CON ALETAS'),
  null,
  'la afirmación abreviada también se lee: el término es del propio campo'
);

-- ═══════════════════════ 3. Un número tiene que estar ═══════════════════════

select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000023', '80'::jsonb, '48 MM'),
  'la cita no trae ese número',
  'el ancho no se redondea desde otra cifra'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000023', '48'::jsonb, '48 MM'),
  null,
  'el número que está escrito sí se lee'
);

-- ══════════════════════ 4. La puerta de escritura ══════════════════════════

select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000041', 'nr_compound',
    '"Orgánico"'::jsonb, 'METALICA', 'prueba') ->> 'verdict',
  'rejected',
  'la RPC rechaza la salida adversarial, no sólo la función pura'
);
select is(
  (select count(*)::int from public.spec_facts
   where subject_id = '99d50000-0000-4000-8000-000000000041'),
  0,
  'una lectura rechazada no deja hecho: la duda no escribe'
);

-- Una cita inventada, aunque el valor sea el correcto.
select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000041', 'nr_compound',
    '"Metálico"'::jsonb, 'COMPUESTO METALICO SINTERIZADO', 'prueba')
    ->> 'reason',
  'la cita no está en el texto del producto',
  'la cita se comprueba contra el texto real, no contra el prompt'
);

select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000041', 'nr_compound',
    '"Metálico"'::jsonb, 'METALICA', 'prueba') ->> 'verdict',
  'recorded',
  'la lectura verificable sí se guarda'
);
select is(
  (select source from public.spec_facts
   where subject_id = '99d50000-0000-4000-8000-000000000041'),
  'name_reading',
  'y entra con su propia procedencia, no disfrazada de ficha del taller'
);
select is(
  (select sv.label from public.spec_facts f
   join public.spec_fact_values fv on fv.fact_id = f.id
   join public.spec_definition_values sv on sv.id = fv.value_id
   where f.subject_id = '99d50000-0000-4000-8000-000000000041'),
  'Metálico',
  'el valor queda ligado al vocabulario de la ficha'
);

-- Idempotente: repetir la misma lectura no duplica ni multiplica el valor.
select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000041', 'nr_compound',
    '"Metálico"'::jsonb, 'METALICA', 'prueba') ->> 'verdict',
  'recorded',
  'repetir la lectura es inocuo'
);
select is(
  (select count(*)::int from public.spec_facts
   where subject_id = '99d50000-0000-4000-8000-000000000041'),
  1,
  'y no deja dos hechos del mismo campo'
);
select is(
  (select count(*)::int from public.spec_fact_values fv
   join public.spec_facts f on f.id = fv.fact_id
   where f.subject_id = '99d50000-0000-4000-8000-000000000041'),
  1,
  'ni dos valores en el mismo hecho'
);

-- ═════════════ 5. Una persona manda sobre una lectura ══════════════════════

insert into public.spec_facts(
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_boolean, source, confirmed
) values (
  '99d50000-0000-4000-8000-000000000001', 'product',
  '99d50000-0000-4000-8000-000000000043',
  '99d50000-0000-4000-8000-000000000022', false, 'mechanic', true
);
select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000043', 'nr_finned',
    'true'::jsonb, 'Con Aletas de Calor', 'prueba') ->> 'verdict',
  'kept_existing',
  'el mecánico dijo que no y la lectura no lo pisa'
);
select is(
  (select value_boolean from public.spec_facts
   where subject_id = '99d50000-0000-4000-8000-000000000043'
     and spec_definition_id = '99d50000-0000-4000-8000-000000000022'),
  false,
  'el dato de la persona queda intacto'
);

-- ═════════════ 6. La evidencia caduca cuando el texto cambia ═══════════════

select is(
  public.assistant_inventory_technical_predicate_source_internal_v1(
    '99d50000-0000-4000-8000-000000000001',
    '99d50000-0000-4000-8000-000000000041',
    'nr_compound', 'in', '["Metálico"]'::jsonb, '', ''),
  'name_reading',
  'mientras el nombre sea el que se leyó, la lectura prueba el campo'
);

update public.products
set name = 'Pastilla Freno Shimano J04C'
where id = '99d50000-0000-4000-8000-000000000041';

select is(
  public.assistant_inventory_technical_predicate_source_internal_v1(
    '99d50000-0000-4000-8000-000000000001',
    '99d50000-0000-4000-8000-000000000041',
    'nr_compound', 'in', '["Metálico"]'::jsonb, '', ''),
  'unresolved',
  'cambiado el nombre, la lectura deja de valer sola: vuelve a ser silencio'
);
select isnt(
  (select count(*)::int from public.spec_facts
   where subject_id = '99d50000-0000-4000-8000-000000000041'), 0,
  'y no hace falta borrar la fila para que deje de contar'
);

-- ═══════════ 7. La procedencia sólo cuenta donde se habilitó ═══════════════

select ok(
  public.supply_need_evidence_is_complete_internal_v1(
    '[{"field":"nr_compound","source":"name_reading"}]'::jsonb),
  'en el carril de compras una lectura verificada sí completa la evidencia'
);
select ok(
  not public.supply_need_evidence_is_complete_internal_v1(
    '[{"field":"nr_compound","source":"name_reading"},
      {"field":"nr_finned","source":"unresolved"}]'::jsonb),
  'pero un campo en silencio sigue dejando la fila sin comprobar'
);
select ok(
  not public.supply_need_evidence_is_complete_internal_v1(
    '[{"field":"nr_compound","source":"inferred"}]'::jsonb),
  'y una procedencia que nadie habilitó no entra por parecerse'
);

-- ══════════ 8. Los bordes que la revisión encontró en el diff ══════════════

-- (5) Una lista de valores no se resuelve a medias: cada lectura reemplazaba
--     la lista entera, así que dos lecturas correctas se pisaban en silencio.
insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, sort_order
) values (
  '99d50000-0000-4000-8000-000000000024',
  '99d50000-0000-4000-8000-000000000001',
  'nr_uses', 'Usos', 'multi_select', '[]'::jsonb, '{}'::jsonb,
  true, false, true, true, true, 4
);
insert into public.spec_definition_values(
  id, tenant_id, spec_definition_id, code, label, sort_order, is_active
) values (
  '99d50000-0000-4000-8000-000000000034',
  '99d50000-0000-4000-8000-000000000001',
  '99d50000-0000-4000-8000-000000000024', 'mtb', 'Montaña', 1, true
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000024', '"Montaña"'::jsonb, 'Montaña'),
  'el servidor todavía no sabe leer una lista de valores',
  'media ficha se parece más a una ficha completa que ninguna: se rechaza'
);

-- (5) Y una cita no puede ser el catálogo entero.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000021', '"Metálico"'::jsonb,
    'METALICA ' || repeat('x ', 120)),
  'la cita es demasiado larga',
  'sin tope, pegar todo el texto haría que cualquier valor quedara citado'
);
select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000042', 'nr_width_mm',
    '48'::jsonb, '48 MM', repeat('m', 81)) ->> 'reason',
  'el nombre del modelo es demasiado largo',
  'el nombre del modelo también viene de afuera y también se acota'
);

-- (3) La vigencia cae si cambia el VOCABULARIO, no sólo el nombre. Ninguna de
--     estas tres cosas toca el texto del producto.
select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000042', 'nr_compound',
    '"Semi-Metálico"'::jsonb, 'SEMI METALICA', 'prueba') ->> 'verdict',
  'recorded',
  'la lectura del segundo producto entra'
);
select is(
  public.assistant_inventory_technical_predicate_source_internal_v1(
    '99d50000-0000-4000-8000-000000000001',
    '99d50000-0000-4000-8000-000000000042',
    'nr_compound', 'in', '["Semi-Metálico"]'::jsonb, '', ''),
  'name_reading',
  'y prueba el campo mientras el vocabulario sea el que se juzgó'
);

update public.spec_definition_values
set label = 'Semi-Metálico Sinterizado'
where id = '99d50000-0000-4000-8000-000000000033';

select is(
  public.assistant_inventory_technical_predicate_source_internal_v1(
    '99d50000-0000-4000-8000-000000000001',
    '99d50000-0000-4000-8000-000000000042',
    'nr_compound', 'in', '["Semi-Metálico Sinterizado"]'::jsonb, '', ''),
  'unresolved',
  'renombrada la etiqueta, la cita vieja deja de sostenerla sola'
);

-- (2) Una fila completa por lectura no puede salir rotulada sin verificar.
select is(
  public.supply_need_match_state_internal_v1(
    '[{"field":"a","source":"name_reading"},
      {"field":"b","source":"name_reading"}]'::jsonb, 2),
  'strong',
  'todo probado es comprobado, venga de la ficha o de la lectura'
);
-- El rótulo y el botón usan la MISMA lista, o una fila sale comprobada para
-- uno y parcial para el otro. Pasó en producción con las dos primeras filas
-- de la necesidad de cambios traseros.
select is(
  public.supply_need_match_state_internal_v1(
    '[{"field":"a","source":"name_reading"},
      {"field":"b","source":"identity_fallback"}]'::jsonb, 2),
  'strong',
  'la identidad curada también completa: no puede rotularse parcial'
);
select ok(
  (public.supply_need_match_state_internal_v1(
     '[{"field":"a","source":"name_reading"},
       {"field":"b","source":"identity_fallback"}]'::jsonb, 2) = 'strong')
  = public.supply_need_evidence_is_complete_internal_v1(
     '[{"field":"a","source":"name_reading"},
       {"field":"b","source":"identity_fallback"}]'::jsonb),
  'los dos juicios coinciden, que es lo único que impide que se separen'
);
select is(
  public.supply_need_match_state_internal_v1(
    '[{"field":"a","source":"name_reading"},
      {"field":"b","source":"unresolved"}]'::jsonb, 2),
  'weak',
  'con un campo en silencio sigue siendo parcial, no comprobada'
);
select ok(
  public.supply_need_evidence_is_complete_internal_v1(
    '[{"field":"a","source":"name_reading"},
      {"field":"b","source":"name_reading"}]'::jsonb),
  'y el rótulo y el botón dicen lo mismo'
);

-- (4) La persona gana de verdad: recupera la procedencia y retira el recibo.
select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000043', 'nr_compound',
    '"Orgánico"'::jsonb, 'Organica', 'prueba') ->> 'verdict',
  'recorded',
  'primero la lectura ocupa el campo'
);
select is(
  public.save_product_spec_facts_v1(
    '99d50000-0000-4000-8000-000000000043',
    array['99d50000-0000-4000-8000-000000000021'::uuid],
    jsonb_build_object(
      '99d50000-0000-4000-8000-000000000021',
      jsonb_build_object('labels', jsonb_build_array('Metálico')))),
  1,
  'y después la persona escribe encima'
);
select is(
  (select source from public.spec_facts
   where subject_id = '99d50000-0000-4000-8000-000000000043'
     and spec_definition_id = '99d50000-0000-4000-8000-000000000021'),
  'mechanic',
  'el dato queda con la procedencia de quien lo escribió'
);
select is(
  (select count(*)::int from public.spec_fact_readings r
   join public.spec_facts f on f.id = r.fact_id
   where f.subject_id = '99d50000-0000-4000-8000-000000000043'),
  0,
  'y sin un recibo que diga que lo respalda una cita que ya no lo sostiene'
);
select is(
  (select sv.label from public.spec_facts f
   join public.spec_fact_values fv on fv.fact_id = f.id
   join public.spec_definition_values sv on sv.id = fv.value_id
   where f.subject_id = '99d50000-0000-4000-8000-000000000043'
     and f.spec_definition_id = '99d50000-0000-4000-8000-000000000021'),
  'Metálico',
  'con el valor que puso la persona, no el que leyó el modelo'
);

-- (6) El recibo no puede pertenecer a otro taller que su hecho.
select throws_ok(
  $$insert into public.spec_fact_readings(
      fact_id, tenant_id, definition_id, source_text, source_digest,
      vocabulary_digest, quote, model)
    select f.id, '99d50000-0000-4000-8000-000000000002', f.spec_definition_id,
           'x', 'y', 'z', 'q', 'm'
    from public.spec_facts f
    where f.subject_id = '99d50000-0000-4000-8000-000000000043'
      and f.spec_definition_id = '99d50000-0000-4000-8000-000000000021'
    limit 1$$,
  '23503',
  NULL,
  'la base impide que el recibo sea de otro taller que el hecho'
);

-- ═══════ 9. La cita distingue el valor; no repite la etiqueta entera ═══════
--
-- Salido de una necesidad real: las etiquetas del taller traen palabras
-- clasificadoras (`Ecosistema Shimano`) y formas alternativas separadas por
-- barra (`SGS / larga`). Ninguna cita de un nombre de producto va a repetirlas
-- enteras, y exigirlo rechazaba las lecturas honestas junto con las falsas.
insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, sort_order
) values (
  '99d50000-0000-4000-8000-000000000025',
  '99d50000-0000-4000-8000-000000000001',
  'nr_cage', 'Largo de caja', 'single_select', '[]'::jsonb, '{}'::jsonb,
  true, false, true, true, true, 5
);
insert into public.spec_definition_values(
  id, tenant_id, spec_definition_id, code, label, sort_order, is_active
) values
  ('99d50000-0000-4000-8000-000000000035',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000025', 'ss', 'SS / corta', 1, true),
  ('99d50000-0000-4000-8000-000000000036',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000025', 'gs', 'GS / media', 2, true),
  ('99d50000-0000-4000-8000-000000000037',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000025', 'sgs', 'SGS / larga', 3, true);

select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"SGS / larga"'::jsonb, 'SGS'),
  null,
  'la sigla del fabricante basta: distingue el valor de sus hermanos'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025',
    '"SGS / larga"'::jsonb, 'PATA LARGA'),
  null,
  'y la misma cosa dicha en castellano también, porque la barra son formas '
  'alternativas y no una conjunción'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"SS / corta"'::jsonb, 'SGS'),
  'la cita no dice ese valor',
  'la sigla de otro largo sigue muerta: SS no es SGS'
);
-- Una sigla de dos letras es una palabra. Sin esto, `SS / corta` se quedaba
-- sin su único token distintivo y dos lecturas honestas del catálogo real
-- morían por eso.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"SS / corta"'::jsonb, 'SS'),
  null,
  'y la propia sigla sí prueba su valor, aunque tenga dos letras'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"GS / media"'::jsonb, 'SS'),
  'la cita no dice ese valor',
  'sin que una sigla corta contagie a la de al lado'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"GS / media"'::jsonb, 'SGS'),
  'la cita no dice ese valor',
  'ni la que se le parece por dentro: una palabra corta no tolera flexión'
);

-- La palabra clasificadora que ningún proveedor escribe.
insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, sort_order
) values (
  '99d50000-0000-4000-8000-000000000026',
  '99d50000-0000-4000-8000-000000000001',
  'nr_eco', 'Ecosistema', 'single_select', '[]'::jsonb, '{}'::jsonb,
  true, false, true, true, true, 6
);
insert into public.spec_definition_values(
  id, tenant_id, spec_definition_id, code, label, sort_order, is_active
) values
  ('99d50000-0000-4000-8000-000000000038',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000026', 'shi', 'Ecosistema Shimano',
   1, true),
  ('99d50000-0000-4000-8000-000000000039',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000026', 'sra', 'Ecosistema SRAM', 2, true);

select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000026',
    '"Ecosistema Shimano"'::jsonb, 'SHIMANO'),
  null,
  'la marca sola distingue el ecosistema: la palabra que clasifica la comparten'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000026',
    '"Ecosistema SRAM"'::jsonb, 'SHIMANO'),
  'la cita no dice ese valor',
  'y normalizar al ecosistema contrario sigue siendo mentira'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000026',
    '"Ecosistema Shimano"'::jsonb, 'Sun Race'),
  'la cita no dice ese valor',
  'una cita real de la fila tampoco vale si nombra otra marca'
);

-- ═══════ 10. Lo que la revisión del diff encontró después de la 280 ════════

-- (c) La huella del vocabulario incluye la descripción del campo, porque el
--     lector booleano saca de ahí sus sinónimos: cambiarla cambia lo que una
--     cita prueba, y una lectura vieja no puede seguir vigente.
create temporary table huella_antes as
select public.spec_definition_vocabulary_digest_internal_v1(
  '99d50000-0000-4000-8000-000000000022') as h;

update public.spec_definitions
set description = 'Aletas o disipador: refrigeración de la pastilla.'
where id = '99d50000-0000-4000-8000-000000000022';

select isnt(
  (select h from huella_antes),
  public.spec_definition_vocabulary_digest_internal_v1(
    '99d50000-0000-4000-8000-000000000022'),
  'cambiar la descripción cambia la huella: el lector booleano saca de ahí sus '
  'sinónimos, así que una lectura vieja no puede seguir vigente'
);

-- Y con esa descripción nueva, «CON DISIPADOR» pasa a decir algo: el
-- vocabulario lo declara la ficha, no una lista escrita a mano.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000022', 'true'::jsonb, 'CON DISIPADOR'),
  null,
  'el taller enseña la palabra en la ficha y el servidor la acepta'
);

-- (d) El invariante que hace innecesario ganar la carrera: un recibo NO PUEDE
--     existir sobre un hecho que no es una lectura, gane quien gane.
select throws_ok(
  $$insert into public.spec_fact_readings(
      fact_id, tenant_id, definition_id, source_text, source_digest,
      vocabulary_digest, quote, model)
    select f.id, f.tenant_id, f.spec_definition_id, 'x', 'y', 'z', 'q', 'm'
    from public.spec_facts f
    where f.subject_id = '99d50000-0000-4000-8000-000000000043'
      and f.source = 'mechanic'
    limit 1$$,
  '23514',
  NULL,
  'un recibo no puede colgar de un dato del mecánico'
);

-- Y si una lectura ya tenía recibo y una persona se queda con el campo, el
-- recibo se va solo: el orden de llegada deja de importar.
select is(
  public.record_product_spec_reading_v1(
    '99d50000-0000-4000-8000-000000000042', 'nr_cage',
    '"SGS / larga"'::jsonb, 'SEMI METALICA 48 MM', 'prueba') ->> 'verdict',
  'rejected',
  'una cita que no dice el valor no deja recibo ni para empezar'
);
select is(
  (select count(*)::int from public.spec_fact_readings r
   join public.spec_facts f on f.id = r.fact_id
   where f.subject_id = '99d50000-0000-4000-8000-000000000042'
     and f.source <> 'name_reading'),
  0,
  'y no queda ningún recibo sobre un hecho que no sea una lectura'
);

-- (d) Los dos que escriben el mismo campo piden el MISMO candado. Un pgTAP
--     corre en una sola sesión, así que la carrera no se puede provocar acá:
--     lo que se afirma es lo que la hace inofensiva — la misma llave, y el
--     invariante de arriba, que no depende de quién gane.
select ok(
  (select prosrc from pg_proc where proname = 'record_product_spec_reading_v1')
    like '%pg_advisory_xact_lock%' || '%:spec_fact:%',
  'la lectura se serializa por producto'
);
select ok(
  (select prosrc from pg_proc where proname = 'save_product_spec_facts_v1')
    like '%pg_advisory_xact_lock%' || '%:spec_fact:%',
  'y el guardado manual toma esa misma llave'
);

-- **Vaciar un criterio compite con el lector, y por eso el candado va antes
-- del borrado.** El guardado manual empieza borrando los campos que la
-- plantilla incluye y el payload no trae; si tomara la llave después, una
-- lectura en vuelo reinsertaría justo el campo que la persona acaba de
-- vaciar. Y una sola llave por producto —no por campo— evita además que dos
-- guardados con los campos en distinto orden se traben entre sí.
select ok(
  position('pg_advisory_xact_lock' in
    (select prosrc from pg_proc where proname = 'save_product_spec_facts_v1'))
  < position('delete from public.spec_facts' in
    (select prosrc from pg_proc where proname = 'save_product_spec_facts_v1')),
  'el candado se toma antes de vaciar nada'
);
select ok(
  (select prosrc from pg_proc where proname = 'save_product_spec_facts_v1')
    like '%:spec_fact:'' || p_product_id::text, 0%',
  'y la llave es sólo el producto, así que dos guardados con los campos en '
  'distinto orden no se traban entre sí'
);

-- El efecto que eso protege: vaciar deja el campo vacío, y una lectura
-- posterior sobre un producto cuya persona ya decidió no lo resucita.
select is(
  public.save_product_spec_facts_v1(
    '99d50000-0000-4000-8000-000000000043',
    array['99d50000-0000-4000-8000-000000000021'::uuid],
    '{}'::jsonb),
  0,
  'vaciar el criterio no escribe ningún hecho'
);
select is(
  (select count(*)::int from public.spec_facts
   where subject_id = '99d50000-0000-4000-8000-000000000043'
     and spec_definition_id = '99d50000-0000-4000-8000-000000000021'),
  0,
  'y el campo queda vacío de verdad'
);
select is(
  (select count(*)::int from public.spec_fact_readings r
   join public.spec_facts f on f.id = r.fact_id
   where f.subject_id = '99d50000-0000-4000-8000-000000000043'),
  0,
  'sin dejar el recibo huérfano de la lectura que hubo antes'
);

-- (e) Las dos huellas del recibo no pueden faltar.
select is(
  (select count(*)::int from information_schema.columns
   where table_schema = 'public' and table_name = 'spec_fact_readings'
     and column_name in ('definition_id', 'vocabulary_digest')
     and is_nullable = 'NO'),
  2,
  'las dos huellas del recibo no pueden faltar'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spec_fact_readings'::regclass and contype = 'f'
      and pg_get_constraintdef(oid) like '%(fact_id, tenant_id, definition_id)%'
  ),
  'el recibo queda amarrado al mismo hecho, taller y campo'
);

-- ══════ 11. Adversariales del puntaje, sobre las formas reales de etiqueta ══

-- Palabras comunes entre hermanos: la que comparten no distingue nada, y la
-- cita que sólo la trae no puede elegir por su cuenta.
insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, sort_order
) values (
  '99d50000-0000-4000-8000-000000000027',
  '99d50000-0000-4000-8000-000000000001',
  'nr_mount', 'Montaje corona', 'single_select', '[]'::jsonb, '{}'::jsonb,
  true, false, true, true, true, 7
);
insert into public.spec_definition_values(
  id, tenant_id, spec_definition_id, code, label, sort_order, is_active
) values
  ('99d50000-0000-4000-8000-00000000003a',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000027', 'dms', 'Direct mount Shimano',
   1, true),
  ('99d50000-0000-4000-8000-00000000003b',
   '99d50000-0000-4000-8000-000000000001',
   '99d50000-0000-4000-8000-000000000027', 'dmr', 'Direct mount SRAM',
   2, true);

select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000027',
    '"Direct mount Shimano"'::jsonb, 'DIRECT MOUNT'),
  'la cita no distingue entre dos valores del campo',
  'la parte que los hermanos comparten no elige por su cuenta'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000027',
    '"Direct mount Shimano"'::jsonb, 'DIRECT MOUNT SHIMANO'),
  null,
  'con la palabra que sí los separa, la lectura entra'
);

-- Sinónimos con barra: cada forma prueba el valor, ninguna prueba a su vecino.
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"SGS / larga"'::jsonb, 'SGS'),
  null,
  'la sigla'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"SGS / larga"'::jsonb, 'LARGA'),
  null,
  'y la palabra en castellano, que es la otra forma de decir lo mismo'
);
select is(
  public.spec_reading_rejection_internal_v1(
    '99d50000-0000-4000-8000-000000000025', '"GS / media"'::jsonb, 'LARGA'),
  'la cita no dice ese valor',
  'sin que una forma le sirva al vecino'
);

select * from finish();
rollback;
