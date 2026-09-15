-- Los seis bordes de la lectura del nombre, corregidos hacia adelante.
--
-- `20260831260000` quedo aplicado y sellado; esto lo corrige sin tocarlo. Los
-- seis salieron de la revision del diff, y ninguno es de una necesidad
-- concreta: son de la forma del mecanismo.
--
--  1. **Una negacion explicita si prueba `false`.** Rechazar todo booleano
--     falso confundia dos cosas distintas: que un nombre que no menciona algo
--     no lo niega --cierto-- con que un nombre que dice `SIN ALETAS` no diga
--     nada --falso--. Y ya habia un lector con esa semantica, usado por las dos
--     orillas del calce; aca se usa **esa misma regla** en vez de una segunda.
--  2. **Una fila completa no puede seguir rotulada sin verificar.** El estado
--     se decidia con una lista que no incluia la procedencia nueva, asi que
--     una fila con todos sus criterios probados salia `unverified` y con
--     `evidenceComplete = true`: el rotulo contradecia al boton.
--  3. **La vigencia tambien cae si cambia el vocabulario.** Atarla solo al
--     nombre dejaba viva una cita que ya no sostiene su valor cuando alguien
--     renombra la etiqueta, agrega un valor hermano mas especifico o cambia el
--     nombre del campo booleano.
--  4. **La persona gana de verdad.** El guardado manual pisaba el valor pero
--     no la procedencia: el dato del mecanico quedaba con `source =
--     'name_reading'` y con el recibo de una cita que ya no lo sostiene.
--  5. **Lo que no se sabe resolver se rechaza, no se resuelve a medias.** Una
--     lectura de `multi_select` reemplazaba la lista entera por un solo
--     miembro, asi que dos lecturas correctas se pisaban en silencio.
--  6. **El recibo no puede pertenecer a otro taller que el hecho.**

-- ---------------------------------------------------------------------------
-- 1. La negacion explicita, con la regla que ya existia.
-- ---------------------------------------------------------------------------
--
-- Espejo en SQL de `supplierBooleanFromFieldVocabulary`, en
-- `lib/shared/services/supplier_spec_extraction.dart`. Son dos
-- implementaciones de una sola regla, y eso se paga: van amarradas por una
-- tabla de casos que se afirma en los dos lados -- `spec_name_reading_evidence`
-- en pgTAP y `catalog_name_reading_test.dart` en Dart. Si una cambia sin la
-- otra, esas pruebas se caen.
--
-- El servidor no puede delegarlo en el cliente: el cliente es justamente la
-- parte que podria estar equivocada o mentir.

create or replace function public.spec_boolean_field_vocabulary_internal_v1(
  p_label text, p_description text)
returns text[]
language plpgsql
immutable
as $function$
declare
  v_auxiliares text[] := array[
    'trae', 'tiene', 'incluye', 'indica', 'si', 'el', 'la', 'los', 'las',
    'de', 'del', 'con', 'sin', 'por', 'para', 'y', 'o', 'un', 'una', 'es',
    'viene', 'declarado', 'esta'];
  v_terminos text[] := array[]::text[];
  v_frases text[];
  v_frase text;
  v_palabras text[];
begin
  -- La etiqueta del campo siempre; y la cabeza de la descripcion cuando es
  -- una lista de sinonimos y no una explicacion --las que empiezan con
  -- "Indica..." describen el campo, no lo nombran--.
  v_frases := array[p_label];
  if p_description is not null and position(':' in p_description) > 1
     and public.assistant_normalize_query_internal_v1(
           substr(p_description, 1, position(':' in p_description) - 1)
         ) not like 'indica%' then
    v_frases := v_frases || regexp_split_to_array(
      substr(p_description, 1, position(':' in p_description) - 1),
      '\s+o\s+|,');
  end if;

  foreach v_frase in array v_frases loop
    if v_frase is null or btrim(v_frase) = '' then continue; end if;
    select array_agg(w order by ord) into v_palabras
    from unnest(string_to_array(
      public.assistant_normalize_query_internal_v1(v_frase), ' '))
      with ordinality as t(w, ord)
    where w <> '' and not (w = any(v_auxiliares));
    if v_palabras is null or array_length(v_palabras, 1) is null then
      continue;
    end if;
    -- Una sola palabra corta no aporta: `Ancho` respaldaria cualquier cosa.
    if array_length(v_palabras, 1) = 1 and length(v_palabras[1]) < 6 then
      continue;
    end if;
    v_terminos := v_terminos || array_to_string(v_palabras, ' ');
    v_terminos := v_terminos || (
      select coalesce(array_agg(w), array[]::text[])
      from unnest(v_palabras) as t(w) where length(w) >= 6);
  end loop;

  select coalesce(array_agg(distinct t), array[]::text[])
  into v_terminos from unnest(v_terminos) as u(t);
  return v_terminos;
end;
$function$;

-- Que dice ese texto sobre el booleano que la ficha nombra: si, no, o nada.
-- `null` es ambiguo o mudo, y las dos cosas se tratan igual: no se escribe.
create or replace function public.spec_boolean_from_field_vocabulary_internal_v1(
  p_text text, p_label text, p_description text)
returns boolean
language plpgsql
stable
as $function$
declare
  v_terminos text[] := public.spec_boolean_field_vocabulary_internal_v1(
    p_label, p_description);
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
  if array_length(v_terminos, 1) is null then return null; end if;
  v_tokens := string_to_array(
    public.assistant_normalize_query_internal_v1(coalesce(p_text, '')), ' ');
  if array_length(v_tokens, 1) is null then return null; end if;

  foreach v_termino in array v_terminos loop
    v_partes := string_to_array(v_termino, ' ');
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
        -- La negacion viaja delante y a no mas de dos palabras: `SIN ALETAS`,
        -- `NO trae aletas`. Mas lejos ya no se sabe a que niega.
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

-- ---------------------------------------------------------------------------
-- 3 y 6. El recibo: vocabulario y pertenencia.
-- ---------------------------------------------------------------------------

-- La huella del vocabulario con que se juzgo la cita. Cambia si se renombra la
-- etiqueta elegida, si se renombra el campo, o si aparece o se retira un valor
-- hermano -- que es lo que puede volver ambigua una cita que no lo era.
create or replace function public.spec_definition_vocabulary_digest_internal_v1(
  p_definition_id uuid)
returns text
language sql
stable
as $function$
  select encode(sha256(convert_to(
    coalesce((
      select d.label || E'\x1f' || d.data_type from public.spec_definitions d
      where d.id = p_definition_id), '') || E'\x1f' ||
    coalesce((
      select string_agg(v.label, E'\x1f' order by v.sort_order, v.id)
      from public.spec_definition_values v
      where v.spec_definition_id = p_definition_id and v.is_active is true
    ), ''), 'UTF8')), 'hex');
$function$;

alter table public.spec_fact_readings
  add column if not exists vocabulary_digest text;
alter table public.spec_fact_readings
  add column if not exists definition_id uuid;

-- Una lectura sin huella de vocabulario no queda vigente por omision: se le
-- calcula la que corresponde ahora, y a partir de aqui cualquier cambio la
-- caduca.
update public.spec_fact_readings r
set definition_id = f.spec_definition_id,
    vocabulary_digest = public.spec_definition_vocabulary_digest_internal_v1(
      f.spec_definition_id)
from public.spec_facts f
where f.id = r.fact_id and r.definition_id is null;

-- 6. El recibo pertenece al mismo taller que el hecho, y lo impone la base.
--
-- El orden importa: la clave ajena cuelga del indice unico, asi que se retira
-- primero o el propio forward no se puede volver a correr.
alter table public.spec_fact_readings
  drop constraint if exists spec_fact_readings_belongs_to_its_fact;
alter table public.spec_fact_readings
  drop constraint if exists spec_fact_readings_fact_id_fkey;
alter table public.spec_facts
  drop constraint if exists spec_facts_id_tenant_unique;
alter table public.spec_facts
  add constraint spec_facts_id_tenant_unique unique (id, tenant_id);
alter table public.spec_fact_readings
  add constraint spec_fact_readings_belongs_to_its_fact
  foreign key (fact_id, tenant_id)
  references public.spec_facts (id, tenant_id) on delete cascade;

-- ---------------------------------------------------------------------------
-- 1 y 5. El veredicto, corregido.
-- ---------------------------------------------------------------------------

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
  v_elegida integer;
  v_mejor integer;
  v_empate integer;
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

    select public.spec_label_coverage_internal_v1(
             v_quote, public.assistant_normalize_query_internal_v1(v.label))
    into v_elegida
    from public.spec_definition_values v
    where v.spec_definition_id = p_definition_id
      and v.is_active is true
      and public.assistant_normalize_query_internal_v1(v.label) = v_wanted
    limit 1;
    if v_elegida is null then
      return 'la cita no dice ese valor';
    end if;

    select max(cobertura), count(*) filter (where cobertura = v_elegida)
    into v_mejor, v_empate
    from (
      select public.spec_label_coverage_internal_v1(
               v_quote,
               public.assistant_normalize_query_internal_v1(v.label)
             ) as cobertura
      from public.spec_definition_values v
      where v.spec_definition_id = p_definition_id
        and v.is_active is true
        and public.assistant_normalize_query_internal_v1(v.label) <> v_wanted
    ) hermanas;
    if v_mejor is not null and v_mejor > v_elegida then
      return 'la cita describe mejor otro valor del campo';
    end if;
    if coalesce(v_empate, 0) > 0 then
      return 'la cita no distingue entre dos valores del campo';
    end if;
    return null;

  elsif v_def.data_type = 'multi_select' then
    -- **Lo que no se sabe resolver se rechaza entero.** Una lista se lee de a
    -- un miembro y cada lectura reemplazaba la lista completa, asi que dos
    -- lecturas correctas se pisaban y la ultima se quedaba sola con la ficha.
    -- Guardar solo una es peor que no guardar ninguna: parece una ficha
    -- completa y es media.
    return 'el servidor todavía no sabe leer una lista de valores';

  elsif v_def.data_type = 'boolean' then
    if jsonb_typeof(p_value) <> 'boolean' then
      return 'el valor no es un sí o un no';
    end if;
    -- **La misma regla de las dos orillas.** Un nombre que dice `SIN ALETAS`
    -- prueba la ausencia tanto como `CON ALETAS` prueba la presencia; lo que
    -- no prueba nada es un nombre que no la menciona, y eso se distingue solo
    -- leyendo, no rechazando toda negacion.
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

-- ---------------------------------------------------------------------------
-- La puerta de escritura, con el vocabulario amarrado y los topes.
-- ---------------------------------------------------------------------------

create or replace function public.record_product_spec_reading_v1(
  p_product_id uuid,
  p_field_key text,
  p_value jsonb,
  p_quote text,
  p_model text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_texto text;
  v_digest text;
  v_vocabulario text;
  v_def record;
  v_rechazo text;
  v_existente record;
  v_fact_id uuid;
  v_valor_id uuid;
begin
  if v_tenant_id is null then
    raise exception 'Sin inquilino' using errcode = '42501';
  end if;
  if length(coalesce(p_model, '')) > 80 then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'el nombre del modelo es demasiado largo');
  end if;

  select concat_ws(' ', p.name, p.description) into v_texto
  from public.products p
  where p.id = p_product_id and p.tenant_id = v_tenant_id;
  if not found then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'el producto no es de este taller');
  end if;

  v_digest := encode(sha256(convert_to(v_texto, 'UTF8')), 'hex');

  if position(
       public.assistant_normalize_query_internal_v1(coalesce(p_quote, ''))
       in public.assistant_normalize_query_internal_v1(v_texto)) = 0
     or coalesce(btrim(p_quote), '') = '' then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'la cita no está en el texto del producto');
  end if;

  select d.id, d.data_type into v_def
  from public.spec_definitions d
  where d.key = p_field_key
    and (d.tenant_id is null or d.tenant_id = v_tenant_id)
    and d.is_filterable is true
  order by (d.tenant_id is not null) desc
  limit 1;
  if not found then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'el campo no existe o no es filtrable');
  end if;

  v_rechazo := public.spec_reading_rejection_internal_v1(
    v_def.id, p_value, p_quote);
  if v_rechazo is not null then
    return jsonb_build_object('verdict', 'rejected', 'reason', v_rechazo);
  end if;

  select f.id, f.source into v_existente
  from public.spec_facts f
  where f.tenant_id = v_tenant_id
    and f.subject_type = 'product'
    and f.subject_id = p_product_id
    and f.spec_definition_id = v_def.id
    and f.subject_scope is null;
  if found and v_existente.source <> 'name_reading' then
    return jsonb_build_object('verdict', 'kept_existing',
      'reason', 'el campo ya tiene un dato de ' || v_existente.source);
  end if;

  if v_def.data_type = 'single_select' then
    select v.id into v_valor_id
    from public.spec_definition_values v
    where v.spec_definition_id = v_def.id and v.is_active is true
      and public.assistant_normalize_query_internal_v1(v.label)
        = public.assistant_normalize_query_internal_v1(p_value #>> '{}')
    limit 1;
    if v_valor_id is null then
      return jsonb_build_object('verdict', 'rejected',
        'reason', 'el valor no está en la lista del campo');
    end if;
  end if;

  if v_existente.id is not null then
    v_fact_id := v_existente.id;
    update public.spec_facts set
      value_number = case when v_def.data_type = 'number'
        then (p_value #>> '{}')::numeric else null end,
      value_boolean = case when v_def.data_type = 'boolean'
        then (p_value #>> '{}')::boolean else null end,
      value_text = null,
      updated_at = now()
    where id = v_fact_id;
  else
    insert into public.spec_facts (
      tenant_id, subject_type, subject_id, spec_definition_id,
      value_number, value_boolean, value_text, source, confirmed)
    values (
      v_tenant_id, 'product', p_product_id, v_def.id,
      case when v_def.data_type = 'number'
        then (p_value #>> '{}')::numeric end,
      case when v_def.data_type = 'boolean'
        then (p_value #>> '{}')::boolean end,
      null, 'name_reading', false)
    returning id into v_fact_id;
  end if;

  if v_valor_id is not null then
    delete from public.spec_fact_values where fact_id = v_fact_id;
    insert into public.spec_fact_values (fact_id, value_id, position)
    values (v_fact_id, v_valor_id, 0);
  end if;

  v_vocabulario := public.spec_definition_vocabulary_digest_internal_v1(
    v_def.id);

  insert into public.spec_fact_readings (
    fact_id, tenant_id, definition_id, source_text, source_digest,
    vocabulary_digest, quote, model)
  values (v_fact_id, v_tenant_id, v_def.id, v_texto, v_digest,
          v_vocabulario, btrim(p_quote),
          coalesce(nullif(btrim(p_model), ''), 'desconocido'))
  on conflict (fact_id) do update set
    definition_id = excluded.definition_id,
    source_text = excluded.source_text,
    source_digest = excluded.source_digest,
    vocabulary_digest = excluded.vocabulary_digest,
    quote = excluded.quote,
    model = excluded.model,
    read_at = now();

  return jsonb_build_object('verdict', 'recorded', 'factId', v_fact_id,
    'digest', v_digest);
end;
$function$;

revoke all on function public.record_product_spec_reading_v1(
  uuid, text, jsonb, text, text) from public;
grant execute on function public.record_product_spec_reading_v1(
  uuid, text, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. La vigencia tambien mira el vocabulario.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_inventory_technical_predicate_source_internal_v1(p_tenant_id uuid, p_product_id uuid, p_field_key text, p_operator text, p_values jsonb, p_identity_surface text, p_identity_raw text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_definition record;
  v_value record;
  v_match boolean := false;
  v_candidate text;
  v_candidate_normalized text;
  v_number numeric;
  v_first numeric;
  v_second numeric;
  v_boolean boolean;
  v_found boolean := false;
  v_texto text;
begin
  select definition.data_type, definition.allowed_values
  into v_definition
  from public.spec_definitions definition
  where definition.key = p_field_key
    and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    and definition.is_filterable is true
  order by (definition.tenant_id is not null) desc
  limit 1;
  if not found then return 'unresolved'; end if;

  -- El hecho sale del registro unificado. Los valores de lista se arman desde
  -- `spec_fact_values`, así que la ETIQUETA con la que se compara es la actual
  -- del vocabulario y no una copia congelada: renombrar un valor no rompe un
  -- filtro que ya funcionaba.
  select f.value_text, f.value_number, f.value_boolean, f.source,
    (
      select string_agg(sv.label, ', ' order by fv.position)
      from public.spec_fact_values fv
      join public.spec_definition_values sv on sv.id = fv.value_id
      where fv.fact_id = f.id
    ) as value_option,
    (
      select jsonb_agg(sv.label order by fv.position)
      from public.spec_fact_values fv
      join public.spec_definition_values sv on sv.id = fv.value_id
      where fv.fact_id = f.id
    ) as value_json,
    null::text as display_value,
    (select r.source_digest from public.spec_fact_readings r
      where r.fact_id = f.id) as source_digest,
    (select r.vocabulary_digest from public.spec_fact_readings r
      where r.fact_id = f.id) as vocabulary_digest,
    f.spec_definition_id as definition_id
  into v_value
  from public.spec_facts f
  join public.spec_definitions definition
    on definition.id = f.spec_definition_id
   and definition.key = p_field_key
   and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
  where f.tenant_id = p_tenant_id
    and f.subject_type = 'product'
    and f.subject_id = p_product_id
    and f.subject_scope is null
  order by (f.source <> 'name_reading') desc,
           (definition.tenant_id is not null) desc
  limit 1;
  v_found := found;

  -- **Una lectura vale para el texto que se leyó.** Si el nombre cambió, el
  -- digest no calza y el hecho se ignora entero: vuelve a ser silencio, que es
  -- la respuesta correcta a «ya no sé si esto seguía diciéndolo».
  if v_found and v_value.source = 'name_reading' then
    select concat_ws(' ', p.name, p.description) into v_texto
    from public.products p
    where p.id = p_product_id and p.tenant_id = p_tenant_id;
    if v_value.source_digest is null
       or v_texto is null
       or v_value.source_digest
          <> encode(sha256(convert_to(v_texto, 'UTF8')), 'hex') then
      v_found := false;
    end if;
    -- **Y el vocabulario con que se juzgo la cita.** Atar la vigencia solo al
    -- nombre dejaba viva una lectura que ya no se sostiene: renombrar la
    -- etiqueta elegida, cambiar el nombre del campo, o agregar un valor
    -- hermano mas especifico son tres formas de que la misma cita deje de
    -- decir lo que decia. Ninguna toca el nombre del producto.
    if v_found and (
         v_value.vocabulary_digest is null
         or v_value.vocabulary_digest
            <> public.spec_definition_vocabulary_digest_internal_v1(
                 v_value.definition_id)) then
      v_found := false;
    end if;
  end if;

  if v_found then
    if v_definition.data_type = 'number' then
      if v_value.value_number is null then return 'conflict'; end if;
      v_number := v_value.value_number;
      v_first := (p_values ->> 0)::numeric;
      if p_operator = 'eq' then v_match := v_number = v_first;
      elsif p_operator = 'neq' then v_match := v_number <> v_first;
      elsif p_operator = 'lt' then v_match := v_number < v_first;
      elsif p_operator = 'lte' then v_match := v_number <= v_first;
      elsif p_operator = 'gt' then v_match := v_number > v_first;
      elsif p_operator = 'gte' then v_match := v_number >= v_first;
      elsif p_operator = 'between' then
        v_second := (p_values ->> 1)::numeric;
        v_match := v_number between least(v_first, v_second)
          and greatest(v_first, v_second);
      elsif p_operator = 'in' then
        v_match := exists (
          select 1 from jsonb_array_elements(p_values) requested(value)
          where v_number = (requested.value #>> '{}')::numeric
        );
      end if;
    elsif v_definition.data_type = 'boolean' then
      if v_value.value_boolean is null then return 'conflict'; end if;
      v_boolean := (p_values ->> 0)::boolean;
      if p_operator = 'eq' then v_match := v_value.value_boolean = v_boolean;
      elsif p_operator = 'neq' then v_match := v_value.value_boolean <> v_boolean;
      end if;
    elsif v_definition.data_type in ('single_select', 'multi_select', 'text') then
      if p_operator = 'contains' then
        v_candidate_normalized := public.assistant_normalize_query_internal_v1(
          p_values ->> 0
        );
        v_match := position(v_candidate_normalized in
          public.assistant_normalize_query_internal_v1(concat_ws(' ',
            v_value.value_text, v_value.value_option, v_value.display_value,
            v_value.value_json::text
          ))) > 0;
      else
        v_match := exists (
          select 1
          from jsonb_array_elements(p_values) requested(value)
          where public.assistant_normalize_query_internal_v1(
              requested.value #>> '{}'
            ) in (
              public.assistant_normalize_query_internal_v1(v_value.value_text),
              public.assistant_normalize_query_internal_v1(v_value.value_option),
              public.assistant_normalize_query_internal_v1(v_value.display_value)
            )
            or (
              jsonb_typeof(v_value.value_json) = 'array'
              and exists (
                select 1
                from jsonb_array_elements(v_value.value_json) member(value)
                where jsonb_typeof(member.value) in ('string', 'number', 'boolean')
                  and public.assistant_normalize_query_internal_v1(
                    member.value #>> '{}'
                  ) = public.assistant_normalize_query_internal_v1(
                    requested.value #>> '{}'
                  )
              )
            )
        );
        if p_operator = 'neq' then v_match := not v_match; end if;
      end if;
    end if;
    -- **La procedencia viaja.** Una lectura del nombre no se disfraza de ficha
    -- del taller: sale con su propio token y cada consumidor decide si la
    -- acepta. Un `conflict` sí es un conflicto venga de donde venga.
    return case
      when not v_match then 'conflict'
      when v_value.source = 'name_reading' then 'name_reading'
      else 'product_spec' end;
  end if;

  -- Curated identity may fill only exact equality/membership for an empty
  -- ficha. It is never a range engine: 68x122.5 cannot prove "eje < 125".
  if p_operator in ('eq', 'in') then
    for v_candidate in
      select requested.value #>> '{}'
      from jsonb_array_elements(p_values) requested(value)
    loop
      v_candidate_normalized := public.assistant_normalize_query_internal_v1(
        v_candidate
      );
      if position(
           ' ' || v_candidate_normalized || ' '
           in ' ' || coalesce(p_identity_surface, '') || ' '
         ) > 0
         or (
           v_candidate_normalized ~ '^[0-9]+(?:[.]?[0-9]+)?$'
           and coalesce(p_identity_raw, '') ~ (
             '(^|[^0-9.])' || replace(v_candidate_normalized, '.', '[.]') ||
             '([^0-9.]|$)'
           )
         ) then
        return 'identity_fallback';
      end if;
    end loop;
  end if;
  return 'unresolved';
end;
$function$

;

-- ---------------------------------------------------------------------------
-- 2. El estado tiene que decir lo mismo que el boton.
-- ---------------------------------------------------------------------------

create or replace function public.supply_need_match_state_internal_v1(p_detail jsonb, p_predicate_count integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select case
    when coalesce(p_predicate_count, 0) = 0 then 'no_criteria'
    -- La ficha contradice el criterio: eso no se muestra en ninguna parte.
    when exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' = 'conflict'
    ) then 'conflict'
    -- Todo verificado. Una lectura del nombre que el servidor comprobo cuenta
    -- igual que la ficha: si no contara, una fila con TODOS sus criterios
    -- probados salia rotulada `unverified` mientras su propio
    -- `evidenceComplete` decia que si -- el rotulo contra el boton.
    when not exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' not in ('product_spec', 'name_reading')
    ) then 'strong'
    -- Algo se establecio y nada contradice. Ese producto NO es indistinguible
    -- de uno del que no se sabe nada.
    when exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' in (
        'product_spec', 'identity_fallback', 'name_reading')
    ) then 'weak'
    else 'unverified'
  end
$function$;

-- ---------------------------------------------------------------------------
-- 4. El guardado manual retira el recibo y recupera la procedencia.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_product_spec_facts_v1(p_product_id uuid, p_definition_ids uuid[], p_values jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_tenant uuid := public.user_tenant_id();
  v_definicion uuid;
  v_tipo text;
  v_entrada jsonb;
  v_fact uuid;
  v_escritos integer := 0;
begin
  if v_tenant is null then
    raise exception 'sin tenant' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.products
    where id = p_product_id and tenant_id = v_tenant
  ) then
    raise exception 'el producto no pertenece a este tenant' using errcode = '42501';
  end if;

  -- Lo que la plantilla incluye y el payload no trae, se borra: vaciar un
  -- campo es parte de guardar, no una operación aparte.
  delete from public.spec_facts f
  where f.tenant_id = v_tenant and f.subject_type = 'product'
    and f.subject_id = p_product_id and f.subject_scope is null
    and f.spec_definition_id = any(p_definition_ids)
    and not (p_values ? f.spec_definition_id::text);

  for v_definicion in
    select unnest(p_definition_ids)
  loop
    v_entrada := p_values -> v_definicion::text;
    continue when v_entrada is null;

    select data_type into v_tipo from public.spec_definitions where id = v_definicion;
    continue when v_tipo is null;

    insert into public.spec_facts (
      tenant_id, subject_type, subject_id, spec_definition_id,
      value_number, value_boolean, value_text, source, confirmed
    ) values (
      v_tenant, 'product', p_product_id, v_definicion,
      case when v_tipo = 'number'
           then nullif(v_entrada ->> 'number', '')::numeric end,
      case when v_tipo = 'boolean'
           then (v_entrada ->> 'boolean')::boolean end,
      case when v_tipo not in ('number','boolean','single_select','multi_select')
           then nullif(v_entrada ->> 'text', '') end,
      'mechanic', false
    )
    on conflict (tenant_id, subject_type, subject_id, spec_definition_id,
                 coalesce(subject_scope, ''))
    do update set
      value_number = excluded.value_number,
      value_boolean = excluded.value_boolean,
      value_text = excluded.value_text,
      -- **La persona gana de verdad.** Sin esto, guardar encima de una lectura
      -- del nombre dejaba el valor del mecanico con `source = 'name_reading'`
      -- y con el recibo de una cita que ya no lo sostiene: procedencia y
      -- respaldo falsos, y ademas el hecho caducaba solo al cambiar el nombre
      -- del producto, borrando en silencio lo que una persona escribio.
      source = excluded.source,
      confirmed = excluded.confirmed,
      updated_at = now()
    returning id into v_fact;

    -- El recibo se retira: ya no hay ninguna lectura que respaldar.
    delete from public.spec_fact_readings where fact_id = v_fact;
    delete from public.spec_fact_values where fact_id = v_fact;

    if v_tipo in ('single_select','multi_select')
       and jsonb_typeof(v_entrada -> 'labels') = 'array' then
      insert into public.spec_fact_values (fact_id, value_id, position)
      select v_fact, sv.id, (elem.ordinality - 1)::integer
      from jsonb_array_elements_text(v_entrada -> 'labels')
        with ordinality as elem(etiqueta, ordinality)
      join public.spec_definition_values sv
        on sv.spec_definition_id = v_definicion and sv.label = elem.etiqueta
      on conflict do nothing;
    end if;

    v_escritos := v_escritos + 1;
  end loop;

  return v_escritos;
end;
$function$

;
