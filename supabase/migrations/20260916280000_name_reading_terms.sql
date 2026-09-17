-- Lectura de nombres: el vocabulario de tienda entra como términos de lectura.
--
-- El lector de nombres (`record_product_spec_reading_v1`) sólo aceptaba una
-- cita que compartiera raíces con la etiqueta de la opción («Cierre rápido»)
-- o con las palabras largas del rótulo de un booleano («Para freno de disco»
-- → «freno disco»). Los nombres del catálogo hablan como la tienda: «QR»,
-- «c/bloqueo», «disco», «(cl)», «FreeWheel», «Núcleo 8-9-10», «C/ Cubre»,
-- «W/O CG», «perforado», «macizo». El 2026-09-16, con 50 mazas a 2,3 campos
-- de 23, quedó claro que la primera pasada de nombres había dejado en el
-- nombre lo que el lector no podía nombrar.
--
-- Cada opción de una lista y cada campo booleano puede declarar ahora sus
-- **términos de lectura**: frases normalizadas que, si aparecen enteras en la
-- cita, nombran esa opción (o afirman / niegan el booleano) con la misma
-- fuerza que la etiqueta completa. El resto no cambia: la cita sigue teniendo
-- que estar en el texto del producto, la opción elegida sigue teniendo que
-- ganarle a sus hermanas con la misma cita (dos opciones con término en la
-- cita empatan y se rechaza), la negación («sin bloqueo») sigue viajando
-- delante, y el recibo de la lectura guarda el vocabulario que se usó (el
-- digest incluye ahora los términos).
--
-- Los términos son datos de las definiciones globales, no código: se
-- corrigen con un update, y el simulador offline los lee del catálogo.

alter table public.spec_definition_values
  add column if not exists reading_terms text[] not null default '{}'::text[];
alter table public.spec_definitions
  add column if not exists reading_terms text[] not null default '{}'::text[];
alter table public.spec_definitions
  add column if not exists reading_terms_false text[] not null default '{}'::text[];

comment on column public.spec_definition_values.reading_terms is
  'Frases de tienda (normalizadas) que nombran esta opción en una cita del nombre: «qr» y «bloqueo» para «Cierre rápido».';
comment on column public.spec_definitions.reading_terms is
  'Booleanos: frases que afirman el campo en una cita («disco» para «Para freno de disco»); una negación delante («sin», «no») lo niega.';
comment on column public.spec_definitions.reading_terms_false is
  'Booleanos: frases que niegan el campo por sí mismas («macizo» para «Eje hueco»).';

-- ¿Alguna de estas frases aparece entera en la cita normalizada?
create or replace function public.spec_terms_hit_internal_v1(
  p_quote_normalized text, p_terms text[])
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select coalesce(bool_or(
    position(' ' || public.assistant_normalize_query_internal_v1(t) || ' '
             in ' ' || coalesce(p_quote_normalized, '') || ' ') > 0), false)
  from unnest(coalesce(p_terms, '{}'::text[])) as u(t)
  where public.assistant_normalize_query_internal_v1(t) <> '';
$function$;

-- La lectura booleana sobre una lista de términos cualquiera: cada término
-- que aparece vota sí, salvo que «sin», «no» o «nunca» vayan hasta dos
-- palabras delante; votos contradictorios o ninguno devuelven null.
create or replace function public.spec_boolean_from_terms_internal_v1(
  p_text text, p_terminos text[])
returns boolean
language plpgsql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_tokens text[];
  v_termino text;
  v_partes text[];
  v_vistos boolean[] := array[]::boolean[];
  v_resultado boolean;
  i integer;
  j integer;
  v_calza boolean;
  v_negado boolean;
  v_atras integer;
begin
  if p_terminos is null or array_length(p_terminos, 1) is null then
    return null;
  end if;
  v_tokens := string_to_array(
    public.assistant_normalize_query_internal_v1(coalesce(p_text, '')), ' ');
  if array_length(v_tokens, 1) is null then return null; end if;

  foreach v_termino in array p_terminos loop
    v_partes := string_to_array(
      public.assistant_normalize_query_internal_v1(v_termino), ' ');
    if v_partes is null or array_length(v_partes, 1) is null
       or v_partes[1] = '' then
      continue;
    end if;
    i := 1;
    while i + array_length(v_partes, 1) - 1 <= array_length(v_tokens, 1) loop
      v_calza := true;
      for j in 1 .. array_length(v_partes, 1) loop
        if v_tokens[i + j - 1] <> v_partes[j] then
          v_calza := false;
          exit;
        end if;
      end loop;
      if v_calza then
        v_negado := false;
        for v_atras in 1 .. 2 loop
          if i - v_atras < 1 then exit; end if;
          if v_tokens[i - v_atras] in ('sin', 'no', 'nunca') then
            v_negado := true;
            exit;
          end if;
        end loop;
        v_vistos := v_vistos || (not v_negado);
      end if;
      i := i + 1;
    end loop;
  end loop;

  select case when count(distinct v) = 1 then bool_and(v) else null end
  into v_resultado from unnest(v_vistos) as t(v);
  return v_resultado;
end;
$function$;

-- La función de vocabulario del rótulo conserva su firma y ahora delega.
create or replace function public.spec_boolean_from_field_vocabulary_internal_v1(
  p_text text, p_label text, p_description text)
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select public.spec_boolean_from_terms_internal_v1(
    p_text, public.spec_boolean_field_vocabulary_internal_v1(p_label, p_description));
$function$;

create or replace function public.spec_reading_rejection_internal_v1(
  p_definition_id uuid, p_value jsonb, p_quote text)
returns text
language plpgsql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_def record;
  v_quote text := public.assistant_normalize_query_internal_v1(
    coalesce(p_quote, ''));
  v_wanted text;
  v_elegida numeric[];
  v_mejor numeric[];
  v_numero numeric;
  v_leido boolean;
  v_negativo boolean;
begin
  select d.data_type, d.label, d.description, d.reading_terms, d.reading_terms_false
  into v_def
  from public.spec_definitions d where d.id = p_definition_id;
  if not found then return 'el campo no existe'; end if;
  if v_quote = '' then return 'la cita viene vacía'; end if;
  -- Una cita es un pedazo, no el catalogo entero: sin tope, el modelo puede
  -- pegar el texto completo y cualquier valor queda "citado".
  if length(p_quote) > 200 then return 'la cita es demasiado larga'; end if;

  if v_def.data_type = 'single_select' then
    v_wanted := public.assistant_normalize_query_internal_v1(
      coalesce(p_value #>> '{}', ''));
    if v_wanted = '' then return 'el valor viene vacío'; end if;

    -- Un término de lectura presente en la cita vale como la etiqueta entera
    -- (fracción 1) y más que cualquier cobertura parcial de una hermana.
    select case when public.spec_terms_hit_internal_v1(v_quote, v.reading_terms)
                then array[1, 1000]::numeric[]
                else public.spec_label_score_internal_v1(
                       v_quote, public.assistant_normalize_query_internal_v1(v.label))
           end
    into v_elegida
    from public.spec_definition_values v
    where v.spec_definition_id = p_definition_id
      and v.is_active is true
      and public.assistant_normalize_query_internal_v1(v.label) = v_wanted
    limit 1;
    if v_elegida is null or v_elegida[2] = 0 then
      return 'la cita no dice ese valor';
    end if;

    -- El mejor de los hermanos con la MISMA cita, con sus propios términos.
    select max(puntaje) into v_mejor
    from (
      select case when public.spec_terms_hit_internal_v1(v_quote, v.reading_terms)
                  then array[1, 1000]::numeric[]
                  else public.spec_label_score_internal_v1(
                         v_quote,
                         public.assistant_normalize_query_internal_v1(v.label))
             end as puntaje
      from public.spec_definition_values v
      where v.spec_definition_id = p_definition_id
        and v.is_active is true
        and public.assistant_normalize_query_internal_v1(v.label) <> v_wanted
    ) hermanas;
    if v_mejor is not null and v_mejor > v_elegida then
      return 'la cita describe mejor otro valor del campo';
    end if;
    if v_mejor is not null and v_mejor = v_elegida then
      return 'la cita no distingue entre dos valores del campo';
    end if;
    return null;

  elsif v_def.data_type = 'multi_select' then
    -- Lo que no se sabe resolver se rechaza entero: una lista leída de un
    -- nombre es casi siempre parcial y media ficha fabrica contradicciones.
    return 'el servidor todavía no sabe leer una lista de valores';

  elsif v_def.data_type = 'boolean' then
    if jsonb_typeof(p_value) <> 'boolean' then
      return 'el valor no es un sí o un no';
    end if;
    -- Rótulo y términos afirmativos votan juntos; un término negativo presente
    -- (y no negado a su vez) dice no, y si además hubo un sí, no se lee.
    v_leido := public.spec_boolean_from_terms_internal_v1(
      p_quote,
      public.spec_boolean_field_vocabulary_internal_v1(v_def.label, v_def.description)
        || coalesce(v_def.reading_terms, '{}'::text[]));
    v_negativo := public.spec_boolean_from_terms_internal_v1(
      p_quote, coalesce(v_def.reading_terms_false, '{}'::text[]));
    if v_negativo is true then
      v_leido := case when v_leido is true then null else false end;
    end if;
    if v_leido is null then
      return 'la cita no dice lo que el campo nombra';
    end if;
    if v_leido <> (p_value #>> '{}')::boolean then
      return 'la cita dice lo contrario';
    end if;
    return null;

  elsif v_def.data_type = 'number' then
    if jsonb_typeof(p_value) is null or jsonb_typeof(p_value) not in ('number','string') then
      return 'el valor no es un número';
    end if;
    begin
      v_numero := (p_value #>> '{}')::numeric;
    exception when numeric_value_out_of_range or invalid_text_representation then
      return 'el valor no es un número';
    end;
    if v_numero is null or v_numero::text in ('NaN','Infinity','-Infinity') then
      return 'el valor no es un número';
    end if;
    -- Only fractional zeroes are insignificant. Keep exact decimal precision
    -- and signed token boundaries; no unit conversion or arithmetic
    -- interpretation of a quote is authorized here.
    v_wanted := trim_scale(v_numero)::text;
    v_wanted := replace(v_wanted, '.', '[.]') ||
      case when position('.' in trim_scale(v_numero)::text)>0 then '0*' else '([.]0+)?' end;
    if v_numero >= 0 then v_wanted := '[+]?' || v_wanted; end if;
    if translate(coalesce(p_quote, ''), '−', '-') !~
      ('(^|[^0-9.,eE+-])' || v_wanted || '($|[^0-9.,eE])') then
      return 'la cita no trae ese número';
    end if;
    return null;
  end if;

  return 'el servidor no sabe comprobar este tipo de campo';
end;
$function$;

-- El recibo de una lectura ata el vocabulario que se usó: ahora con términos.
create or replace function public.spec_definition_vocabulary_digest_internal_v1(
  p_definition_id uuid)
returns text
language sql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select encode(sha256(convert_to(
    coalesce((
      select d.label || E'\x1f' || d.data_type || E'\x1f' || coalesce(d.description, '')
        || E'\x1f' || array_to_string(coalesce(d.reading_terms, '{}'::text[]), E'\x1e')
        || E'\x1f' || array_to_string(coalesce(d.reading_terms_false, '{}'::text[]), E'\x1e')
      from public.spec_definitions d
      where d.id = p_definition_id), '') || E'\x1f' ||
    coalesce((
      select string_agg(
        v.label || E'\x1e' || array_to_string(coalesce(v.reading_terms, '{}'::text[]), E'\x1e'),
        E'\x1f' order by v.sort_order, v.id)
      from public.spec_definition_values v
      where v.spec_definition_id = p_definition_id and v.is_active is true
    ), ''), 'UTF8')), 'hex');
$function$;

-- ───────────────────────── términos de las opciones ─────────────────────────
-- Vocabulario de tienda chilena leído en los nombres del catálogo el
-- 2026-09-16. Cada fila: clave de la definición global, etiqueta exacta de la
-- opción, frases (se normalizan al comparar: minúsculas, sin acentos, sólo
-- letras y números separados por un espacio).
with terms(def_key, option_label, phrases) as (
  values
  ('hub_axle_mount_kind', 'Cierre rápido', array['qr','bloqueo','bloq','c bloqueo','c bloq','con bloqueo','con bloq','quick release']),
  ('hub_axle_mount_kind', 'Eje pasante', array['eje pasante','thru axle','pasante']),
  ('hub_axle_mount_kind', 'Eje con tuercas', array['tuerca','tuercas','c tuerca','con tuerca','con tuercas','eje macizo']),
  ('rotor_mount_type', 'Centerlock', array['cl','center lock','centerlock','centre lock']),
  ('rotor_mount_type', '6 pernos', array['6 bolt','6 bolts','6 tornillos','seis pernos']),
  ('hub_drive_receiver_kind', 'Núcleo de cassette', array['nucleo','microspline','micro spline','cassette','casete','nucleo hg']),
  ('hub_drive_receiver_kind', 'Rosca para piñón (rueda libre)', array['freewheel','free wheel','rueda libre','pinon con hilo','con hilo','para pinon']),
  ('hub_drive_receiver_kind', 'Rosca para piñón fijo', array['fixi','fixie','fixed','pista','flip flop']),
  ('bearing_system', 'Sellados', array['sealed']),
  ('bearing_system', 'Bolas sueltas', array['bolitas','con bolitas','c bolitas','bolas']),
  ('stem_kind', 'Ahead (sin rosca)', array['ahead','a head','aheadset','sin rosca']),
  ('stem_kind', 'De espiga (quill)', array['quill','espiga','con rosca']),
  ('stem_kind', 'Adaptador (quill a ahead)', array['adaptador','adaptadora']),
  ('seatpost_kind', 'Rígida', array['rigida','rigido']),
  ('seatpost_kind', 'Telescópica (dropper)', array['dropper','telescopica']),
  ('seatpost_kind', 'Con suspensión', array['suspension','con resorte','amortiguada']),
  ('chainring_position', 'Único', array['monoplato','mono plato','single','1x']),
  ('braking_surface', 'Llanta', array['v brake','vbrake','patin','patines','tiro lateral','pista','1 2 pista','herradura','cantilever']),
  ('braking_surface', 'Disco', array['disc','rotor']),
  ('compound_type', 'Semi-Metálico', array['semi metal','semimetal','semi metalica','semi metalicas','semimetalica','semimetalicas']),
  ('compound_type', 'Metálico', array['sinterizada','sinterizadas','sintered']),
  ('compound_type', 'Orgánico (resina)', array['resina','organ']),
  ('compound_type', 'Cerámico', array['ceramic']),
  ('pedal_type', 'Plataforma', array['plano','plana','flat']),
  ('pedal_type', 'Automático (clipless)', array['cala','calas','clipless','automatico','spd']),
  ('pedal_type', 'Con rastrales', array['rastrales','rastral']),
  ('body_material', 'Plástico / nylon', array['resina','termoplastico','termoplastica','plast','plastic','composite']),
  ('body_material', 'Aluminio', array['alum','aluminum','alloy','aluminiocnc']),
  ('body_material', 'Acero', array['steel']),
  ('body_material', 'Magnesio', array['mag']),
  ('sold_as', 'Par', array['par','pares','juego','jgo','set','2 unidades','2u']),
  ('sold_as', 'Unidad', array['c u','cada uno','1u']),
  ('pedal_thread_standard', '1/2" x 20 TPI', array['1 2','1 2 x 20']),
  ('pedal_thread', '1/2', array['1 2']),
  ('pedal_thread', '9/16', array['9 16']),
  ('pedal_thread_standard', '9/16" x 20 TPI', array['9 16','9 16 x 20']),
  ('crank_side', 'Izquierda', array['izquerda','izq','left']),
  ('crank_side', 'Derecha', array['der','derecho','right']),
  ('crank_side', 'Par', array['par','juego','jgo']),
  ('declared_purpose', 'Perno de plato', array['corona','coronas','plato','platos','chainring']),
  ('declared_purpose', 'Perno de rotor', array['disco','freno disco','disco freno','rotor']),
  ('declared_purpose', 'Perno de portacaramagiola', array['porta caramayolas','porta caramayola','porta caramagiola','portacaramayola','portacaramagiola','caramayola','caramagiola','portabotella']),
  ('declared_purpose', 'Perno de patilla', array['postiza','patilla','hanger']),
  ('declared_purpose', 'Perno de biela (cuadrado)', array['biela','bielas','eje cuadrado','cuadrado','cuadrada','pedivela']),
  ('head_drive', 'Torx', array['torq','t25','t30']),
  ('head_drive', 'Hexagonal interior (Allen)', array['allen','hex']),
  ('fastener_kind', 'Golilla / espaciador', array['golilla','golillas','espaciadora','espaciador','arandela']),
  ('fastener_kind', 'Perno', array['bolt']),
  ('fastener_kind', 'Tornillo', array['screw']),
  ('fastener_kind', 'Tuerca', array['nut']),
  ('thread', '3/8"', array['3 8']),
  ('thread', '5/16"', array['5 16']),
  ('thread', '1/2"', array['1 2']),
  ('thread', '9/16"', array['9 16']),
  ('bearing_application', 'Maza', array['maza','mazas','rueda','ruedas','eje trasero','eje delantero']),
  ('bearing_application', 'Pedalier', array['motor','thompson','eje thompson','bb']),
  ('bearing_element_retention', 'Con jaula', array['canastillo','enjaulado','enjaulada','jaula','caged']),
  ('bearing_element_retention', 'Complemento completo / sin jaula', array['sueltas','sueltos','sin jaula']),
  ('bearing_supply_form', 'Canastillo con bolas', array['canastillo','enjaulado','enjaulada']),
  ('bearing_supply_form', 'Bolas sueltas', array['en bolsa','bolsa','gruesa','sueltas']),
  ('tool_kind', 'Llave de pedalier', array['extractor motor','extractor de motor','llave motor','motor sellado','bb tool']),
  ('tool_kind', 'Cepillo / limpieza', array['limpiador','escobilla','cepillo','brocha']),
  ('tool_kind', 'Alicate / prensa', array['pinza','pinzas','alicate']),
  ('tool_kind', 'Llave de rayos', array['tira rayos','tirarayos','llave rayos']),
  ('tool_kind', 'Extractor de obús', array['obus','extractor obus']),
  ('tool_kind', 'Extractor de biela', array['extractor biela','extractor perno biela','saca biela']),
  ('tool_kind', 'Herramienta de purga', array['purga','sangrado','bleed']),
  ('tool_kind', 'Corta cadena', array['cortacadena','tronchacadena']),
  ('tool_kind', 'Llave de pedales', array['llave pedal','llave de pedal']),
  ('tool_kind', 'Desmontador de neumático', array['desmontadores','saca cubierta']),
  ('tool_kind', 'Multiherramienta', array['multi herramienta','multitool']),
  ('tool_kind', 'Extractor de cassette / rueda libre', array['extractor cassette','extractor pinon','saca pinon','llave cassette']),
  ('tool_kind', 'Manómetro / bomba de suspensión', array['shock pump']),
  ('chemical_kind', 'Lubricante de cadena (seco)', array['seco','dry']),
  ('chemical_kind', 'Lubricante de cadena (húmedo)', array['humedo','wet']),
  ('chemical_kind', 'Lubricante de cadena (cera)', array['cera','wax']),
  ('chemical_kind', 'Desengrasante', array['degreaser']),
  ('chemical_kind', 'Limpiador', array['cleaner']),
  ('chemical_kind', 'Grasa', array['grease']),
  ('chemical_kind', 'Aceite multiuso', array['multiuso','multi uso','3 en 1']),
  ('container', 'Gotero', array['drip']),
  ('container', 'Aerosol', array['spray']),
  ('container', 'Botella', array['bottle']),
  ('container', 'Bidón / bulk', array['bidon','bulk','galon']),
  ('container', 'Tarro', array['pote']),
  ('repair_kind', 'Kit parches + solución', array['kit','set']),
  ('repair_kind', 'Pegamento / solución', array['pegamento','solucion','cemento']),
  ('repair_kind', 'Parche autoadhesivo', array['glueless','autoadhesivo','sin pegamento']),
  ('repair_kind', 'Parche vulcanizable', array['vulcanizable']),
  ('valve_standard', 'Francesa (Presta)', array['f v','fv','v f','vf','francesa presta']),
  ('valve_standard', 'Auto (Schrader / americana)', array['a v','av','v a','va']),
  ('caliper_mount_interface', 'Post Mount', array['pm','post mount','postmount']),
  ('caliper_mount_interface', 'Flat Mount', array['fm','flat mount','flatmount']),
  ('rear_derailleur_mount_type', 'Con uña / claw', array['apernar','claw','con garra']),
  ('shifter_control_style', 'Giro (twist)', array['giro','twist','revoshift','revo shift','grip shift','gripshift']),
  ('shifter_control_style', 'Gatillo (trigger)', array['gatillo','trigger']),
  ('shifter_control_style', 'Palanca de pulgar', array['pulgar','thumb','thumbshifter']),
  ('shifter_control_style', 'Integrado con la maneta de freno', array['ez fire','ezfire','cambio freno','cambio y freno','st ef']),
  ('fork_kind', 'Rígida', array['rigida','rigido','rigid']),
  ('fork_kind', 'Suspensión (aire)', array['aire','air']),
  ('fork_kind', 'Suspensión (muelle)', array['muelle','resorte','coil','espiral']),
  ('brake_mount', 'Post Mount', array['pm','post mount']),
  ('brake_mount', 'Postes cantilever / V-brake', array['v brake','cantilever']),
  ('drivetrain_mode', 'Single speed / BMX / IGH', array['bmx','single','single speed','1 v','1v','1 vel','fixie','pista']),
  ('drivetrain_mode', 'Derailleur', array['6 vel','7 vel','8 vel','9 vel','10 vel','11 vel','12 vel','6 v','7 v','8 v','9 v','10 v','11 v','12 v','6 7 8','7 8','8 9','9 10','velocidades']),
  ('chain_connector_type', 'Missing link', array['missing','missinglink','quick link','power link','powerlink']),
  ('chain_connector_type', 'Pin', array['pasador']),
  ('chain_connector_type', 'Half link', array['medio eslabon']),
  ('barrel_material', 'Plástico / resina', array['plastic','plastico','plastica']),
  ('barrel_material', 'Aluminio', array['alum','aluminum']),
  ('barrel_material', 'Acero', array['steel']),
  ('pump_kind', 'De pie', array['floor','piso']),
  ('pump_kind', 'Inflador CO2', array['inflador']),
  ('pump_kind', 'Cartucho CO2 (recarga)', array['cartucho','cartuchos','recarga']),
  ('pump_kind', 'Bomba de suspensión', array['shock']),
  ('grip_attachment', 'Lock-on (doble abrazadera)', array['2 lock','doble lock','dual lock','2 abrazaderas']),
  ('grip_attachment', 'Lock-on (una abrazadera)', array['1 lock','single lock']),
  ('grip_attachment', 'Deslizante', array['slide on','sin lock']),
  ('intended_rider', 'Niño', array['nino','ninos','junior','kids','infantil']),
  ('intended_rider', 'Adulto', array['adultos']),
  ('clamp_kind', 'Collarín con cierre rápido', array['bloqueo','qr','quick release','palanca']),
  ('clamp_kind', 'Collarín con perno', array['perno','tornillo','allen']),
  ('clamp_kind', 'Aguja / palanca de repuesto', array['aguja','repuesto']),
  ('kickstand_mount_kind', 'Abrazadera a vaina', array['abrazadera','vaina']),
  ('kickstand_mount_kind', 'Placa central (tornillo)', array['central','placa']),
  ('crankset_construction', 'Dos piezas (integrado)', array['integrado','integrada','hollowtech','2 piezas','dos piezas']),
  ('crankset_construction', 'Tres piezas (motor aparte)', array['3 piezas','tres piezas','cuadrado','eje cuadrado','cotterless']),
  ('crankset_construction', 'Una pieza (americana)', array['americano','una pieza','1 pieza','ashtabula','opc']),
  ('crank_arm_system_construction', 'Tres piezas (eje independiente)', array['3 piezas','para eje','cuadrado','eje cuadrado']),
  ('crank_arm_system_construction', 'Dos piezas (eje solidario al brazo derecho)', array['integrado','integrada','hollowtech','motor integrado']),
  ('crank_arm_system_construction', 'Una pieza (americana / Ashtabula)', array['americana','americano','una pieza','1 pieza']),
  ('headset_part_scope', 'Completa', array['completa','completo','juego','set','juego de direccion']),
  ('cover_material', 'Cuero', array['leather']),
  ('cover_material', 'Sintético', array['sintetico','pu','pvc','vinilo']),
  ('saddle_intended_use', 'Urbano / confort', array['paseo','urbano','urbana','comfort','city']),
  ('material', 'Plástico', array['plastico','plastica','plastic','resina']),
  ('material', 'Aluminio', array['alum','aluminum','alloy']),
  ('material', 'Acero', array['steel']),
  ('material', 'Carbono', array['carbon']),
  ('material', 'Titanio', array['titanium']),
  ('lever_cable_pull', 'Tiro largo (V-brake / disco mecánico tiro largo)', array['v brake','tiro largo','linear pull']),
  ('lever_cable_pull', 'Tiro corto (ruta / cantilever / caliper)', array['ruta','tiro corto','caliper','cantilever']),
  ('brake_actuation', 'Contrapedal', array['contrapedal']),
  ('brake_presentation', 'Par delantero y trasero', array['del tra','del tras','delantero trasero','juego','jgo','set','par']),
  ('tire_bead_type', 'Alambre', array['wire','rigido','rigida']),
  ('tire_bead_type', 'Plegable (kevlar)', array['folding','foldable']),
  ('tire_use', 'Urbano / híbrido', array['urbano','urbana','hibrido','hibrida','city','trekking','paseo']),
  ('tire_use', 'Niño', array['nino','ninos','kids','infantil']),
  ('tire_use', 'Scooter', array['patin electrico','scooter electrico'])
)
update public.spec_definition_values v
set reading_terms = t.phrases
from terms t, public.spec_definitions d
where d.id = v.spec_definition_id and d.tenant_id is null and d.key = t.def_key
  and v.label = t.option_label and v.is_active is true;

-- ───────────────────────── términos de los booleanos ─────────────────────────
with terms(def_key, yes, no) as (
  values
  ('hub_rotor_mount_present', array['disco','disc','para disco','cl','centerlock','6 pernos'], array['v brake','para v brake']),
  ('hub_drive_receiver_present', array['nucleo','microspline','micro spline','cassette','freewheel','free wheel','rueda libre','pinon con hilo','con hilo','fixi','fixie','flip flop'], array[]::text[]),
  ('axle_hollow', array['perforado','perforada','hueco','bloqueo','para bloqueo','quick release','qr'], array['macizo','solido']),
  ('cones_and_locknuts_included', array['completo','completa','con conos','c conos'], array['sin conos','solo eje']),
  ('pad_spring_included', array['spring','w spring','con resorte','resorte','c resorte'], array['sin resorte','w o spring']),
  ('reflectors_included', array['reflector','reflectores','c ref','c reflector','con reflector','reflectante'], array['sin reflector']),
  ('replaceable_pins', array['pines','pins','c pines','con pines','pinchos','c pinchos'], array['sin pines']),
  ('nipples_included', array['niples','nipples','c niples','con niples','con nipples','c nipples'], array['sin niples','sin nipples']),
  ('quick_link_included', array['missing link','missing','conector','c conector','con conector','quick link','power link','con union'], array['sin conector','sin missing']),
  ('crankset_chain_guard_included', array['c cubre','con cubre','cubrecadena','cubre cadena','cubre','c cg','w cg','chainguard','con guarda','guarda'], array['w o cg','sin cubre','sin cg','sin guarda']),
  ('bottom_bracket_included', array['c motor','con motor','motor incluido','motor bsa','incluye motor'], array['sin motor','s motor','w o bb','sin pedalier']),
  ('crank_arm_carries_chainring_mount', array['derecha','der','right','con platos'], array['izquierda','izquerda','izq','left']),
  ('rim_tubeless_ready', array['tlr','tl ready','tubeless'], array[]::text[]),
  ('tire_tubeless_ready', array['tlr','tl ready','tubeless'], array[]::text[]),
  ('valve_core_removable', array['obus desmontable','desmontable'], array[]::text[]),
  ('saddle_cutout', array['canal','con canal','ventana','cut out','cutout'], array[]::text[]),
  ('adjustable_length', array['regulable'], array[]::text[]),
  ('gauge', array['manometro','con manometro','c manometro','gauge'], array['sin manometro']),
  ('hose', array['manguera','con manguera','c manguera'], array['sin manguera']),
  ('frame_mount_included', array['con soporte','c soporte','soporte cuadro'], array['sin soporte']),
  ('lockout', array['lockout','bloqueo','con bloqueo','c bloqueo'], array['sin bloqueo']),
  ('steerer_threaded', array['con hilo','c hilo','con rosca','roscada','roscado'], array['sin hilo','sin rosca','ahead','a head']),
  ('rotor_floating', array['flotante','floating'], array[]::text[]),
  ('narrow_wide', array['narrow','nw','n w'], array[]::text[])
)
update public.spec_definitions d
set reading_terms = t.yes, reading_terms_false = t.no
from terms t
where d.tenant_id is null and d.key = t.def_key and d.data_type = 'boolean';
