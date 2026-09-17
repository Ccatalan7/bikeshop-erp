-- Términos de lectura: la frase más específica gana el empate.
--
-- Con la primera versión dos opciones que tuvieran un término en la cita
-- empataban y la lectura se rechazaba. Eso rompe el caso más común de las
-- presentaciones: «Juego de Frenos Hidráulicos» nombra un «Par delantero y
-- trasero» por la frase entera «juego de frenos», pero también contiene
-- «juego», que es como la tienda nombra un «Par de mecanismos» de herraduras.
-- La frase más larga es la más específica: si una opción calza por «juego de
-- frenos» y la otra sólo por «juego», gana la primera. Dos opciones con la
-- misma frase siguen empatando y la lectura sigue sin escribirse.
--
-- El puntaje de una opción pasa a ser [1, 1000 + largo de la frase más larga
-- que calzó]; una cobertura parcial de la etiqueta sigue por debajo de
-- cualquier término. Y se reparte el vocabulario de las presentaciones: las
-- palabras genéricas («juego», «jgo», «set», «par», «del/tra») nombran el par
-- de mecanismos (herraduras, cálipers), y las frases con «frenos» el par de
-- frenos completos.

-- Largo normalizado de la frase más larga que aparece entera en la cita; 0 si ninguna.
create or replace function public.spec_terms_best_length_internal_v1(
  p_quote_normalized text, p_terms text[])
returns integer
language sql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select coalesce(max(length(public.assistant_normalize_query_internal_v1(t))), 0)
  from unnest(coalesce(p_terms, '{}'::text[])) as u(t)
  where public.assistant_normalize_query_internal_v1(t) <> ''
    and position(' ' || public.assistant_normalize_query_internal_v1(t) || ' '
                 in ' ' || coalesce(p_quote_normalized, '') || ' ') > 0;
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
    -- (fracción 1) y más que cualquier cobertura parcial de una hermana; entre
    -- términos, la frase más larga es la más específica.
    select case when public.spec_terms_hit_internal_v1(v_quote, v.reading_terms)
                then array[1, 1000 + public.spec_terms_best_length_internal_v1(v_quote, v.reading_terms)]::numeric[]
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
                  then array[1, 1000 + public.spec_terms_best_length_internal_v1(v_quote, v.reading_terms)]::numeric[]
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

-- ─────────────── el vocabulario de las presentaciones se reparte ───────────────
update public.spec_definition_values v
set reading_terms = array['juego de frenos','juego de frenos hidraulicos','par de frenos','frenos delantero y trasero','frenos del y tras']
from public.spec_definitions d
where d.id = v.spec_definition_id and d.tenant_id is null and d.key = 'brake_presentation'
  and v.label = 'Par delantero y trasero';

update public.spec_definition_values v
set reading_terms = array['juego','jgo','set','par','del tra','del tras','delantero y trasero','del y tras','par de herraduras','par de calipers']
from public.spec_definitions d
where d.id = v.spec_definition_id and d.tenant_id is null and d.key = 'brake_presentation'
  and v.label = 'Par de mecanismos';

-- ─────────────── tercera tanda de términos que pidieron las reglas ───────────────
with terms(def_key, option_label, phrases) as (
  values
  ('shifter_position', 'Par', array['juego','set','jgo','par']),
  ('front_derailleur_cable_pull', 'Doble tiro (dual pull)', array['abajo arriba','arriba abajo','t abajo arriba','t arriba abajo']),
  ('material', 'Policarbonato / plástico', array['polycarbonato','policarbonato']),
  ('tool_kind', 'Llave de pedales', array['llave pedal','llave de pedal','llave shimano pedal','pedal wrench']),
  ('control_part_kind', 'Noodle V-brake', array['guia freno','guia pasador freno v brake','guia freno curva','tubo freno','pasador freno']),
  ('control_part_kind', 'Guía de cable', array['guia cable','guia de cable'])
)
update public.spec_definition_values v
set reading_terms = coalesce((
  select array_agg(distinct x order by x)
  from unnest(v.reading_terms || t.phrases) as u(x)), '{}'::text[])
from terms t, public.spec_definitions d
where d.id = v.spec_definition_id and d.tenant_id is null and d.key = t.def_key
  and v.label = t.option_label and v.is_active is true;
