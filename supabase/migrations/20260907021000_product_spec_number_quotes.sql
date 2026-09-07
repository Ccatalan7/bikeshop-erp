-- Exact decimal quote checks preserve integer zeroes and signs.
-- No facts, readings, catalogue metadata, identities or stock are rewritten.
begin;
do $preimage$ begin
 if md5(pg_get_functiondef('public.spec_reading_rejection_internal_v1(uuid,jsonb,text)'::regprocedure))
   not in ('80ee75f5935890a01ecf71bf75325558','0a9ca5252a7013e674edd427da58dfa7') then
   raise exception 'Numeric reading preimage drift';
 end if;
end $preimage$;
CREATE OR REPLACE FUNCTION public.spec_reading_rejection_internal_v1(p_definition_id uuid, p_value jsonb, p_quote text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path=pg_catalog,public,pg_temp
AS $function$
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
    -- Only fractional zeroes are insignificant. Trimming text zeroes turned
    -- the integer 10 into 1 and made zero an empty expression. Keep exact
    -- decimal precision and signed token boundaries; no unit conversion or
    -- arithmetic interpretation of a quote is authorized here.
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
alter function public.spec_reading_rejection_internal_v1(uuid,jsonb,text) owner to postgres;
revoke all on function public.spec_reading_rejection_internal_v1(uuid,jsonb,text) from public,anon,authenticated;
do $postimage$ begin
 if md5(pg_get_functiondef('public.spec_reading_rejection_internal_v1(uuid,jsonb,text)'::regprocedure)) is distinct from '0a9ca5252a7013e674edd427da58dfa7' then
   raise exception 'Numeric reading postimage drift';
 end if;
end $postimage$;
commit;
