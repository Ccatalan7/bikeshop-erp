-- La cita distingue el valor; no tiene que repetir la etiqueta entera.
--
-- Salido de una necesidad nueva y real, creada el 2026-08-31 contra el
-- catalogo del taller: "Cambio trasero Shimano de 9 velocidades con caja
-- larga". Los 34 cambios traseros del catalogo no tienen un solo hecho en su
-- ficha, y sus nombres dicen casi todo -- `CAMBIO SHIMANO 6/7V. RD-TX35`,
-- `RD-M2000 ALTUS SGS 9-SPEED`, `RD-M200 6/7/8-VEL. PATA LARGA`.
--
-- Con la regla de cobertura completa, el servidor rechazo las SIETE lecturas
-- probadas contra esos nombres, honestas y adversariales por igual. La causa
-- es de la forma de las etiquetas reales, no de esta familia:
--
--   · `Ecosistema Shimano` trae una palabra clasificadora que ningun nombre de
--     producto va a escribir. Ninguna cita cubre las dos palabras.
--   · `SGS / larga` escribe DOS FORMAS DE DECIR LO MISMO separadas por barra.
--     `SGS` cubre una, `PATA LARGA` cubre la otra, y exigir ambas es exigir
--     que el proveedor escriba las dos.
--
-- La pregunta correcta no es si la cita repite la etiqueta, sino **si la cita
-- distingue este valor de sus hermanos**. Eso se puntua y se compara:
--
--   puntaje = (palabras cubiertas / palabras de la etiqueta, palabras cubiertas)
--
-- y el valor elegido tiene que ganarle estrictamente a todos sus hermanos. La
-- fraccion decide primero -- `METALICA` cubre entero a `Metalico` (1,0) y la
-- mitad de `Semi-Metalico` (0,5), asi que gana el primero -- y el conteo
-- desempata -- `SEMI METALICA` cubre los dos enteros, gana el que cubre mas
-- palabras. Empate en las dos, se rechaza: el servidor no adivina.
--
-- Sigue sin haber una palabra escrita a mano en ningun lado: el vocabulario es
-- el que la ficha declara.

create or replace function public.spec_label_score_internal_v1(
  p_quote_normalized text, p_label_normalized text)
returns numeric[]
language sql
immutable
as $function$
  with palabras as (
    select w from unnest(string_to_array(p_label_normalized, ' ')) as t(w)
    where length(w) >= 3
  ), cubiertas as (
    select count(*) filter (where cubierta) as cubiertas,
           count(*) as total
    from (
      select exists (
        select 1
        from unnest(string_to_array(p_quote_normalized, ' ')) as q(w)
        where public.spec_word_shares_stem_internal_v1(q.w, p.w)
      ) as cubierta
      from palabras p
    ) evaluadas
  )
  select case
    when total = 0 or cubiertas = 0 then array[0, 0]::numeric[]
    else array[round(cubiertas::numeric / total, 6), cubiertas]::numeric[]
  end
  from cubiertas;
$function$;

comment on function public.spec_label_score_internal_v1(text, text) is
  'Cuanto de esta etiqueta dice esta cita: fraccion cubierta y palabras '
  'cubiertas, en ese orden de prioridad. `{0,0}` = no la dice.';

create or replace function public.spec_reading_rejection_internal_v1(
  p_definition_id uuid,
  p_value jsonb,
  p_quote text)
returns text
language plpgsql
stable
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
begin
  select d.data_type, d.label, d.description into v_def
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

    select public.spec_label_score_internal_v1(
             v_quote, public.assistant_normalize_query_internal_v1(v.label))
    into v_elegida
    from public.spec_definition_values v
    where v.spec_definition_id = p_definition_id
      and v.is_active is true
      and public.assistant_normalize_query_internal_v1(v.label) = v_wanted
    limit 1;
    if v_elegida is null or v_elegida[2] = 0 then
      return 'la cita no dice ese valor';
    end if;

    -- El mejor de los hermanos con la MISMA cita.
    select max(puntaje) into v_mejor
    from (
      select public.spec_label_score_internal_v1(
               v_quote,
               public.assistant_normalize_query_internal_v1(v.label)
             ) as puntaje
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
    -- **Lo que no se sabe resolver se rechaza entero.** Y no es solo que dos
    -- lecturas se pisen: una lista leida de un nombre es casi siempre PARCIAL.
    -- `RD-M2000 9-SPEED` declara el 9 y calla el 8, y un cassette de 8 pasaria
    -- a "no cumple" cuando la verdad es "el nombre no lo dice". Media ficha
    -- fabrica contradicciones; ninguna solo deja silencio, que es lo cierto.
    return 'el servidor todavía no sabe leer una lista de valores';

  elsif v_def.data_type = 'boolean' then
    if jsonb_typeof(p_value) <> 'boolean' then
      return 'el valor no es un sí o un no';
    end if;
    v_leido := public.spec_boolean_from_field_vocabulary_internal_v1(
      p_quote, v_def.label, v_def.description);
    if v_leido is null then
      return 'la cita no dice lo que el campo nombra';
    end if;
    if v_leido <> (p_value #>> '{}')::boolean then
      return 'la cita dice lo contrario';
    end if;
    return null;

  elsif v_def.data_type = 'number' then
    begin
      v_numero := (p_value #>> '{}')::numeric;
    exception when others then
      return 'el valor no es un número';
    end;
    if coalesce(p_quote, '') !~ ('(^|[^0-9.])' ||
         replace(trim(trailing '.' from trim(trailing '0' from
           v_numero::text)), '.', '[.]') || '([^0-9.]|$)') then
      return 'la cita no trae ese número';
    end if;
    return null;
  end if;

  return 'el servidor no sabe comprobar este tipo de campo';
end;
$function$;
