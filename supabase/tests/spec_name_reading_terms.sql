begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- El vocabulario de tienda entra como términos de lectura.
--
-- Los nombres del catálogo dicen «QR», «c/bloqueo», «(CL)», «FreeWheel»,
-- «macizo». Antes el lector sólo aceptaba la cita que compartiera raíces con
-- la etiqueta («Cierre rápido»), así que todo ese vocabulario quedaba en el
-- nombre sin entrar a la ficha. Estas pruebas defienden tres cosas:
--   · un término presente vale como la etiqueta entera, y sólo para su opción;
--   · dos opciones con término en la misma cita empatan y NO se lee;
--   · la negación sigue mandando, también sobre los términos, y el recibo
--     (digest) cambia cuando cambia el vocabulario.

select has_column('public', 'spec_definition_values', 'reading_terms',
  'cada opción puede declarar sus frases de tienda');
select has_column('public', 'spec_definitions', 'reading_terms',
  'cada booleano puede declarar frases que lo afirman');
select has_column('public', 'spec_definitions', 'reading_terms_false',
  'cada booleano puede declarar frases que lo niegan');
select has_function('public', 'spec_terms_hit_internal_v1', array['text', 'text[]'],
  'una frase entera dentro de la cita normalizada');
select has_function('public', 'spec_boolean_from_terms_internal_v1', array['text', 'text[]'],
  'la lectura booleana con negación sobre una lista cualquiera');

-- ───────────────────────────── datos de prueba ─────────────────────────────
insert into public.tenants(id, shop_name, currency, timezone) values
  ('99d60000-0000-4000-8000-000000000001', 'Terms Tenant', 'CLP', 'America/Santiago');

insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, sort_order, reading_terms, reading_terms_false
) values
  ('99d60000-0000-4000-8000-000000000021', '99d60000-0000-4000-8000-000000000001',
   'nt_axle_mount', 'Fijación del eje', 'single_select', '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 1, '{}', '{}'),
  ('99d60000-0000-4000-8000-000000000022', '99d60000-0000-4000-8000-000000000001',
   'nt_axle_hollow', 'Eje hueco', 'boolean', '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 2,
   array['perforado', 'para bloqueo', 'qr'], array['macizo', 'solido']),
  ('99d60000-0000-4000-8000-000000000023', '99d60000-0000-4000-8000-000000000001',
   'nt_rotor_present', 'Para freno de disco', 'boolean', '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 3, array['cl', 'centerlock'], '{}');

insert into public.spec_definition_values(
  id, tenant_id, spec_definition_id, code, label, sort_order, is_active, reading_terms
) values
  ('99d60000-0000-4000-8000-000000000031', '99d60000-0000-4000-8000-000000000001',
   '99d60000-0000-4000-8000-000000000021', 'qr', 'Cierre rápido', 1, true,
   array['QR', 'bloqueo', 'c/bloqueo', 'quick release']),
  ('99d60000-0000-4000-8000-000000000032', '99d60000-0000-4000-8000-000000000001',
   '99d60000-0000-4000-8000-000000000021', 'thru', 'Eje pasante', 2, true,
   array['thru axle', 'pasante']),
  ('99d60000-0000-4000-8000-000000000033', '99d60000-0000-4000-8000-000000000001',
   '99d60000-0000-4000-8000-000000000021', 'nuts', 'Eje con tuercas', 3, true,
   array['tuerca', 'tuercas', 'eje macizo']),
  ('99d60000-0000-4000-8000-000000000034', '99d60000-0000-4000-8000-000000000001',
   '99d60000-0000-4000-8000-000000000021', 'bolts', 'Eje hembra con pernos', 4, true,
   '{}');

-- ═════════════════════ 1. el término nombra su opción ═════════════════════

select is(
  public.spec_terms_hit_internal_v1('maza delantera 32h qr negra', array['qr', 'bloqueo']),
  true, 'la sigla QR aparece entera en la cita');
select is(
  public.spec_terms_hit_internal_v1('maza delantera 32h qrx negra', array['qr']),
  false, 'un término es una palabra entera, no un prefijo');
select is(
  public.spec_terms_hit_internal_v1('maza c bloqueo', array['C/Bloqueo']),
  true, 'el término se normaliza igual que la cita (barra → espacio, minúsculas)');
select is(
  public.spec_terms_hit_internal_v1('maza c bloqueo', '{}'::text[]),
  false, 'sin términos nadie acierta');

select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Cierre rápido"'::jsonb, 'QR'),
  null, '«QR» lee «Cierre rápido» aunque no comparta ni una letra con la etiqueta');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Cierre rápido"'::jsonb, 'c/bloqueo'),
  null, '«c/bloqueo» lee «Cierre rápido»');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Eje pasante"'::jsonb, 'QR'),
  'la cita no dice ese valor',
  'un término ajeno no lee esta opción: la cita no la nombra');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Eje pasante"'::jsonb, 'eje qr'),
  'la cita describe mejor otro valor del campo',
  'media etiqueta no le gana al término entero de la hermana');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Eje con tuercas"'::jsonb, 'tuerca'),
  null, 'el singular «tuerca» lee «Eje con tuercas»');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Eje pasante"'::jsonb, 'eje pasante 12mm'),
  null, 'la etiqueta entera sigue leyéndose como antes');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Eje hembra con pernos"'::jsonb, 'pernos'),
  null, 'una opción sin términos se sigue leyendo por su etiqueta');

-- ═══════════════ 2. dos términos en la misma cita: no se lee ═══════════════

select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Eje pasante"'::jsonb, 'pasante tuercas'),
  'la cita no distingue entre dos valores del campo',
  'una cita que nombra dos opciones por frases del mismo largo empata y se rechaza');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Cierre rápido"'::jsonb, 'eje macizo con bloqueo'),
  'la cita describe mejor otro valor del campo',
  '«eje macizo» es más largo que «bloqueo»: la frase más específica gana');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000021', '"Cierre rápido"'::jsonb, 'maza trasera 36h'),
  'la cita no dice ese valor',
  'sin término ni etiqueta en la cita no hay lectura');

-- ═══════════ 2b. entre dos términos, la frase más larga es la más específica ═══════════

insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, sort_order
) values
  ('99d60000-0000-4000-8000-000000000024', '99d60000-0000-4000-8000-000000000001',
   'nt_presentation', 'Presentación', 'single_select', '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 4);
insert into public.spec_definition_values(
  id, tenant_id, spec_definition_id, code, label, sort_order, is_active, reading_terms
) values
  ('99d60000-0000-4000-8000-000000000035', '99d60000-0000-4000-8000-000000000001',
   '99d60000-0000-4000-8000-000000000024', 'mech', 'Par de mecanismos', 1, true,
   array['juego', 'set', 'par']),
  ('99d60000-0000-4000-8000-000000000036', '99d60000-0000-4000-8000-000000000001',
   '99d60000-0000-4000-8000-000000000024', 'full', 'Par delantero y trasero', 2, true,
   array['juego de frenos']);

select is(
  public.spec_terms_best_length_internal_v1('juego de frenos hidraulicos', array['juego', 'juego de frenos']),
  15, 'el largo de la frase más larga que calzó');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000024', '"Par delantero y trasero"'::jsonb, 'Juego de Frenos'),
  null, '«juego de frenos» le gana a «juego»: la frase entera es la más específica');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000024', '"Par de mecanismos"'::jsonb, 'Juego de Frenos'),
  'la cita describe mejor otro valor del campo',
  'y la genérica pierde con la misma cita');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000024', '"Par de mecanismos"'::jsonb, 'Herraduras (Juego)'),
  null, 'sin la frase larga, «juego» solo nombra el par de mecanismos');

-- ══════════════ 3. booleanos: afirmar, negar y la negación delante ══════════════

select is(
  public.spec_boolean_from_terms_internal_v1('eje perforado 3/8', array['perforado']),
  true, 'un término afirmativo presente dice sí');
select is(
  public.spec_boolean_from_terms_internal_v1('eje sin perforar', array['perforado']),
  null, 'una raíz distinta no es el término: nada leído');
select is(
  public.spec_boolean_from_terms_internal_v1('eje sin bloqueo trasero', array['bloqueo']),
  false, '«sin» dos palabras antes niega el término');
select is(
  public.spec_boolean_from_terms_internal_v1('eje con bloqueo y sin bloqueo', array['bloqueo']),
  null, 'un sí y un no en la misma cita no leen nada');

select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000022', 'true'::jsonb, 'eje perforado'),
  null, '«perforado» afirma «Eje hueco» por término');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000022', 'false'::jsonb, 'eje macizo'),
  null, '«macizo» niega «Eje hueco» por término negativo');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000022', 'true'::jsonb, 'eje macizo'),
  'la cita dice lo contrario',
  'con «macizo» no se puede afirmar que es hueco');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000022', 'true'::jsonb, 'eje hueco'),
  null, 'el vocabulario del rótulo sigue valiendo junto a los términos');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000022', 'false'::jsonb, 'eje perforado macizo'),
  'la cita no dice lo que el campo nombra',
  'un sí por término y un no por término negativo se anulan');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000023', 'true'::jsonb, 'maza (cl) 32h'),
  null, '«(CL)» afirma «Para freno de disco»');
select is(
  public.spec_reading_rejection_internal_v1(
    '99d60000-0000-4000-8000-000000000023', 'true'::jsonb, 'maza 32h negra'),
  'la cita no dice lo que el campo nombra',
  'sin rótulo ni término no hay lectura booleana');

-- ═════════════ 4. el recibo cambia cuando cambia el vocabulario ═════════════

select public.spec_definition_vocabulary_digest_internal_v1(
  '99d60000-0000-4000-8000-000000000021') as before_digest \gset
update public.spec_definition_values
set reading_terms = reading_terms || array['bloq']
where id = '99d60000-0000-4000-8000-000000000031';
select isnt(
  public.spec_definition_vocabulary_digest_internal_v1('99d60000-0000-4000-8000-000000000021'),
  :'before_digest',
  'agregar un término a una opción cambia el digest del campo');

select public.spec_definition_vocabulary_digest_internal_v1(
  '99d60000-0000-4000-8000-000000000022') as bool_digest \gset
update public.spec_definitions
set reading_terms_false = reading_terms_false || array['lleno']
where id = '99d60000-0000-4000-8000-000000000022';
select isnt(
  public.spec_definition_vocabulary_digest_internal_v1('99d60000-0000-4000-8000-000000000022'),
  :'bool_digest',
  'agregar un término negativo a un booleano cambia su digest');

-- ══════════ 5. la vieja función de vocabulario del rótulo no cambió ══════════

select is(
  public.spec_boolean_from_field_vocabulary_internal_v1(
    'pastilla con aletas de calor', 'Con Aletas de Calor', null),
  true, 'el vocabulario del rótulo sigue afirmando');
select is(
  public.spec_boolean_from_field_vocabulary_internal_v1(
    'pastilla sin aletas de calor', 'Con Aletas de Calor', null),
  false, 'y sigue negando');

select * from finish();
rollback;
