-- El nombre del producto es evidencia, y el servidor es quien la comprueba.
--
-- Medido el 2026-08-31 sobre el catálogo real del taller: 1.613 productos
-- activos, 45 con descripción de más de 20 caracteres. La ficha del taller
-- está casi vacía y **lo único que hay escrito es el nombre**. Un lector
-- determinista sólo resuelve un campo cuando la palabra pedida aparece literal,
-- así que «METALICA» no contradecía «Orgánico» y 47 de 49 pastillas quedaban
-- sin verificar por silencio.
--
-- Un modelo sí puede leer ese nombre. Lo que no puede es que se le crea. Este
-- forward instala las tres garantías que hacen utilizable esa lectura:
--
--  1. **La cita tiene que sostener el valor.** Que «METALICA» esté en el nombre
--     no autoriza a normalizarlo como «Orgánico». La comprobación usa el
--     vocabulario que la propia ficha declara —`spec_definition_values`— y no
--     una lista de palabras por producto: la cita tiene que cubrir la etiqueta
--     elegida, y ninguna etiqueta hermana puede cubrirla mejor.
--  2. **La evidencia queda amarrada al texto que se leyó.** Se guarda el
--     digest del nombre+descripción del momento de la lectura. Si el nombre
--     cambia, el hecho deja de contar solo, sin que nadie tenga que acordarse
--     de borrarlo.
--  3. **La procedencia es del servidor.** El hecho entra con `source =
--     'name_reading'`, que es un token NUEVO: todos los consumidores que hoy
--     preguntan `in ('product_spec','identity_fallback')` lo ignoran hasta que
--     este mismo archivo los habilite uno por uno. Habilitar es un acto
--     explícito y auditable, no un efecto colateral.
--
-- Y una duda es silencio: si el modelo falla, se demora o su lectura no pasa la
-- comprobación, no se escribe nada y la fila sigue no verificada.

-- ---------------------------------------------------------------------------
-- 1. La procedencia nueva.
-- ---------------------------------------------------------------------------

alter table public.spec_facts drop constraint if exists spec_facts_source_known;
alter table public.spec_facts add constraint spec_facts_source_known
  check (source = any (array[
    'mechanic', 'catalog', 'supplier_text', 'inferred', 'import',
    'name_reading'
  ]));

-- ---------------------------------------------------------------------------
-- 2. El recibo de la lectura: qué texto se leyó y qué pedazo la sostiene.
-- ---------------------------------------------------------------------------

create table if not exists public.spec_fact_readings (
  fact_id uuid primary key
    references public.spec_facts(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  source_text text not null,
  source_digest text not null,
  quote text not null,
  model text not null,
  read_at timestamptz not null default now()
);

create index if not exists spec_fact_readings_tenant
  on public.spec_fact_readings (tenant_id);

alter table public.spec_fact_readings enable row level security;

drop policy if exists spec_fact_readings_select on public.spec_fact_readings;
create policy spec_fact_readings_select on public.spec_fact_readings
  for select using (tenant_id = public.user_tenant_id());

-- Sin política de escritura a propósito: el recibo sólo lo escribe la RPC,
-- que es `security definer` y comprueba antes. Un cliente que pudiera
-- insertarlo a mano podría fabricar el respaldo de un hecho falso.

grant select on public.spec_fact_readings to authenticated;

comment on table public.spec_fact_readings is
  'Qué texto y qué cita sostienen un hecho leído por IA. El digest ata la '
  'evidencia a la versión del texto: si el nombre cambia, el hecho deja de '
  'contar.';

-- ---------------------------------------------------------------------------
-- 3. La compuerta: ¿esta cita sostiene ESTE valor y no otro?
-- ---------------------------------------------------------------------------

create or replace function public.text_common_prefix_len_internal_v1(
  p_a text, p_b text)
returns integer
language sql
immutable
as $function$
  select coalesce(max(g), 0)
  from generate_series(1, least(length(p_a), length(p_b))) g
  where substr(p_a, 1, g) = substr(p_b, 1, g);
$function$;

-- Dos palabras comparten raíz. El español flexiona el final —METALICA contra
-- Metálico— así que el corte es por prefijo común y no por igualdad literal.
-- Una palabra corta no tolera flexión: `TRP` tiene que aparecer como `TRP`, o
-- cualquier palabra de tres letras respaldaría cualquier marca de tres letras.
create or replace function public.spec_word_shares_stem_internal_v1(
  p_quote_word text, p_label_word text)
returns boolean
language sql
immutable
as $function$
  select case
    when p_quote_word is null or p_label_word is null then false
    when length(p_label_word) < 4 or length(p_quote_word) < 4
      then p_quote_word = p_label_word
    else public.text_common_prefix_len_internal_v1(p_quote_word, p_label_word)
      >= greatest(4, ceil(0.75 * least(length(p_quote_word),
                                       length(p_label_word)))::integer)
  end;
$function$;

-- Cuántas palabras de la etiqueta cubre la cita. `null` = no la cubre entera.
--
-- Se exige cobertura COMPLETA porque es lo que distingue a `Metálico` de
-- `Semi-Metálico`: la cita «METALICA» cubre la primera entera y de la segunda
-- sólo la mitad, así que gana la primera; la cita «SEMI METALICA» cubre las
-- dos, y entonces gana la que cubre más palabras. Empatadas, se rechaza: el
-- servidor no adivina.
create or replace function public.spec_label_coverage_internal_v1(
  p_quote_normalized text, p_label_normalized text)
returns integer
language sql
immutable
as $function$
  with palabras as (
    select w from unnest(string_to_array(p_label_normalized, ' ')) as t(w)
    where length(w) >= 3
  ), cubiertas as (
    select p.w,
      exists (
        select 1
        from unnest(string_to_array(p_quote_normalized, ' ')) as q(w)
        where public.spec_word_shares_stem_internal_v1(q.w, p.w)
      ) as cubierta
    from palabras p
  )
  select case
    when (select count(*) from palabras) = 0 then null
    when exists (select 1 from cubiertas where not cubierta) then null
    else (select count(*)::integer from cubiertas)
  end;
$function$;

-- El veredicto del servidor sobre una lectura. Devuelve `null` si la acepta, o
-- la razón del rechazo. No escribe nada: se puede llamar para explicar.
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
begin
  select d.data_type, d.label into v_def
  from public.spec_definitions d where d.id = p_definition_id;
  if not found then return 'el campo no existe'; end if;
  if v_quote = '' then return 'la cita viene vacía'; end if;

  if v_def.data_type in ('single_select', 'multi_select') then
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

    -- Ninguna etiqueta hermana puede cubrirse mejor con la misma cita.
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

  elsif v_def.data_type = 'boolean' then
    -- Sólo la afirmación es comprobable. Un nombre que NO menciona una
    -- característica no la niega —una ausencia no es un cumplimiento— así que
    -- `false` nunca se lee de un nombre. Y la afirmación se comprueba contra
    -- la etiqueta del propio campo, que es el único vocabulario que la ficha
    -- declara para un booleano.
    if jsonb_typeof(p_value) <> 'boolean' then
      return 'el valor no es un sí o un no';
    end if;
    if p_value = 'false'::jsonb then
      return 'un nombre que no lo menciona no lo niega';
    end if;
    if public.spec_label_coverage_internal_v1(
         v_quote,
         public.assistant_normalize_query_internal_v1(v_def.label)) is null then
      return 'la cita no dice lo que el campo nombra';
    end if;
    return null;

  elsif v_def.data_type = 'number' then
    begin
      v_numero := (p_value #>> '{}')::numeric;
    exception when others then
      return 'el valor no es un número';
    end;
    -- El número tiene que estar en la cita, y no pegado a otro número.
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

comment on function public.spec_reading_rejection_internal_v1(uuid, jsonb, text)
  is 'Por qué el servidor rechaza una lectura del nombre. `null` = la acepta. '
     'Usa el vocabulario que declara la ficha, nunca palabras por producto.';

-- ---------------------------------------------------------------------------
-- 4. La puerta de escritura.
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
  v_def record;
  v_rechazo text;
  v_existente record;
  v_fact_id uuid;
  v_valor_texto text;
  v_valor_id uuid;
begin
  if v_tenant_id is null then
    raise exception 'Sin inquilino' using errcode = '42501';
  end if;

  select concat_ws(' ', p.name, p.description) into v_texto
  from public.products p
  where p.id = p_product_id and p.tenant_id = v_tenant_id;
  if not found then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'el producto no es de este taller');
  end if;

  v_digest := encode(sha256(convert_to(v_texto, 'UTF8')), 'hex');

  -- La cita tiene que estar en el texto vigente del producto.
  if position(
       public.assistant_normalize_query_internal_v1(coalesce(p_quote, ''))
       in public.assistant_normalize_query_internal_v1(v_texto)) = 0
     or coalesce(trim(p_quote), '') = '' then
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

  -- **Una lectura nunca pisa a una persona.** El índice único deja un solo
  -- hecho por producto y campo; si ya hay uno de otra procedencia, manda ese.
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

  if v_def.data_type in ('single_select', 'multi_select') then
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

  insert into public.spec_fact_readings (
    fact_id, tenant_id, source_text, source_digest, quote, model)
  values (v_fact_id, v_tenant_id, v_texto, v_digest,
          trim(p_quote), coalesce(nullif(trim(p_model), ''), 'desconocido'))
  on conflict (fact_id) do update set
    source_text = excluded.source_text,
    source_digest = excluded.source_digest,
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

comment on function public.record_product_spec_reading_v1(
  uuid, text, jsonb, text, text)
  is 'Guarda una lectura del nombre como hecho, sólo si el servidor puede '
     'comprobar que la cita sostiene el valor. Idempotente por producto y '
     'campo; nunca pisa un dato de otra procedencia.';

-- ---------------------------------------------------------------------------
-- 5. La lectura caduca sola cuando el texto cambia.
-- ---------------------------------------------------------------------------
--
-- Se reemplaza el juez de procedencia para que (a) distinga de dónde salió el
-- dato y (b) descarte una lectura cuyo texto ya no es el que se leyó. Lo
-- segundo tiene que vivir acá y no en un proceso de limpieza: entre que el
-- nombre cambia y que alguien pase a revisar, el dato viejo estaría probando
-- un requisito con una frase que ya no existe.

create or replace function public.assistant_inventory_technical_predicate_source_internal_v1(p_tenant_id uuid, p_product_id uuid, p_field_key text, p_operator text, p_values jsonb, p_identity_surface text, p_identity_raw text)
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
      where r.fact_id = f.id) as source_digest
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
$function$;

-- ---------------------------------------------------------------------------
-- 6. Habilitar la procedencia, consumidor por consumidor.
-- ---------------------------------------------------------------------------
--
-- Sólo el carril de compras. `assistant_search_inventory_v*` queda como está:
-- sigue ignorando las lecturas del nombre hasta que se decida y se pruebe por
-- separado. Es fail-closed a propósito — un token nuevo no entra en ningún
-- lado por descuido.

create or replace function public.supply_need_evidence_is_complete_internal_v1(p_detail jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(jsonb_array_length(coalesce(p_detail, '[]'::jsonb)), 0) > 0
     and not exists (
       select 1
       from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
       where coalesce(entry.value ->> 'source', 'unresolved')
             not in ('product_spec', 'identity_fallback', 'name_reading')
     );
$function$;

-- purchase_query_products_internal_v1: la lectura del nombre cuenta como ficha en el carril de compras.
CREATE OR REPLACE FUNCTION public.purchase_query_products_internal_v1(p_tenant_id uuid, p_query text, p_only_purchased boolean DEFAULT true)
 RETURNS TABLE(product_id uuid, dropped_words text, dropped_filters text, requested_gamas text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_query text;
  v_inferred jsonb;
  v_inferred_categories uuid[];
  v_predicates jsonb := '[]'::jsonb;
  v_requested_gamas text[];
  v_query_full text;
  v_match_any boolean := false;
  v_dropped_words text;
  v_dropped_filters text;
  v_attempt integer;
  v_found integer := 0;
begin
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  if v_query is null then
    return;
  end if;

  v_inferred := public.assistant_infer_technical_predicates_internal_v1(
    p_tenant_id, p_query
  );
  v_predicates := coalesce(v_inferred -> 'predicates', '[]'::jsonb);
  select array_agg((category.value #>> '{}')::uuid)
  into v_inferred_categories
  from jsonb_array_elements(
    coalesce(v_inferred -> 'categories', '[]'::jsonb)
  ) category(value);
  if jsonb_array_length(v_predicates) > 0
     or v_inferred_categories is not null then
    v_query := nullif(
      public.assistant_normalize_query_internal_v1(
        v_inferred ->> 'residual'
      ), ''
    );
  end if;

  -- La gama se dice con palabras, y esas palabras no están en el nombre de
  -- ningún producto. Se consumen como señal de banda y salen del texto.
  if v_query is not null then
    select array_agg(distinct banda order by banda)
    into v_requested_gamas
    from regexp_split_to_table(v_query, ' +') token
    cross join lateral (
      select case
        when token in ('alta', 'altas', 'premium', 'tope') then 'alta'
        when token in ('media', 'medias', 'intermedia') then 'media'
        when token in ('economica', 'economicas', 'baja', 'bajas',
          'basica', 'basicas', 'barata', 'baratas', 'entrada') then 'economica'
      end banda
    ) mapped
    where banda is not null;

    if v_requested_gamas is not null then
      select nullif(btrim(string_agg(token, ' ')), '')
      into v_query
      from regexp_split_to_table(v_query, ' +') token
      where token not in ('alta', 'altas', 'premium', 'tope', 'media',
        'medias', 'intermedia', 'economica', 'economicas', 'baja', 'bajas',
        'basica', 'basicas', 'barata', 'baratas', 'entrada', 'gama', 'gamas');
    end if;
  end if;

  v_query_full := v_query;

  -- **La respuesta baja un escalón; no se cae de golpe.** Se sueltan filtros de
  -- a uno, del más frágil al más firme. La RAMA nunca se suelta.
  for v_attempt in 1..8 loop
    if v_attempt > 1 and v_found > 0 then
      exit;
    end if;

    if v_attempt = 2 then
      continue when v_query is null
        or (v_inferred_categories is null
            and jsonb_array_length(v_predicates) = 0);
      v_dropped_words := v_query;
      v_query := null;
    elsif v_attempt between 3 and 7 then
      -- **Las medidas se sueltan de a una, la menos cubierta primero.**
      --
      -- Soltarlas en bloque perdía la que importaba: «Cámaras 29 Schrader»
      -- pasaba de 6 productos a 29 —cámaras de 26 y de 700c presentadas como
      -- evidencia de una compra de 29—. Y soltar sólo las que no tienen
      -- cobertura tampoco basta: cuando las dos la tienen por separado y su
      -- COMBINACIÓN no calza, no había nada que soltar y la respuesta quedaba
      -- en cero.
      --
      -- Se suelta una por intento, empezando por la que menos productos toca
      -- en esta rama: la que menos distingue. Así «29» sobrevive a «Schrader».
      continue when jsonb_array_length(v_predicates) = 0
        or v_inferred_categories is null;
      select coalesce(jsonb_agg(medida.value order by medida.ord), '[]'::jsonb)
      into v_predicates
      from (
        select item.value, item.ordinality ord,
          (
            select count(*)
            from public.products product
            where product.tenant_id = p_tenant_id
              and product.is_active is true
              and product.category_id = any(v_inferred_categories)
              and public.assistant_inventory_technical_predicate_source_internal_v1(
                p_tenant_id, product.id,
                item.value ->> 'field',
                item.value ->> 'operator',
                coalesce(item.value -> 'values', '[]'::jsonb),
                public.assistant_normalize_query_internal_v1(concat_ws(' ',
                  product.name, product.brand, product.model,
                  product.manufacturer, product.category_name, product.category
                )),
                unaccent(lower(concat_ws(' ', product.name, product.brand,
                  product.model, product.manufacturer, product.category_name,
                  product.category)))
              ) in ('product_spec', 'identity_fallback', 'name_reading')
          ) cobertura
        from jsonb_array_elements(v_predicates)
          with ordinality as item(value, ordinality)
      ) medida
      where medida.ord <> (
        select ord from (
          select item.ordinality ord,
            (
              select count(*)
              from public.products product
              where product.tenant_id = p_tenant_id
                and product.is_active is true
                and product.category_id = any(v_inferred_categories)
                and public.assistant_inventory_technical_predicate_source_internal_v1(
                  p_tenant_id, product.id,
                  item.value ->> 'field',
                  item.value ->> 'operator',
                  coalesce(item.value -> 'values', '[]'::jsonb),
                  public.assistant_normalize_query_internal_v1(concat_ws(' ',
                    product.name, product.brand, product.model,
                    product.manufacturer, product.category_name,
                    product.category
                  )),
                  unaccent(lower(concat_ws(' ', product.name, product.brand,
                    product.model, product.manufacturer,
                    product.category_name, product.category)))
                ) in ('product_spec', 'identity_fallback', 'name_reading')
            ) cobertura
          from jsonb_array_elements(v_predicates)
            with ordinality as item(value, ordinality)
        ) ranking
        order by cobertura asc, ord desc
        limit 1
      );
      v_dropped_filters := 'la medida menos determinante';
    elsif v_attempt = 8 then
      continue when v_query_full is null
        or not exists (
          select 1 from regexp_split_to_table(v_query_full, ' +') token
          where length(token) >= 3
        );
      v_query := v_query_full;
      v_match_any := true;
      v_dropped_words := null;
      v_dropped_filters := 'la coincidencia de todas las palabras';
    end if;

    return query
    with requested_predicates as (
      select predicate.value ->> 'field' as field_key,
        predicate.value ->> 'operator' as operator,
        coalesce(predicate.value -> 'values', '[]'::jsonb) as values
      from jsonb_array_elements(v_predicates) predicate(value)
    ), universe as materialized (
      select distinct product.id as pid,
        product.category_id,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.brand, product.model, product.manufacturer,
          product.category_name, product.category
        )) identity_surface,
        unaccent(lower(concat_ws(' ', product.name, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category))) identity_raw
      from public.products product
      where product.tenant_id = p_tenant_id
        and product.is_active is true
        and (
          not p_only_purchased
          or exists (
            select 1
            from public.purchase_line_landed_cost_observations_v1 observation
            where observation.tenant_id = p_tenant_id
              and observation.product_id = product.id
              and observation.document_status in ('received', 'paid')
          )
        )
    )
    select universe.pid, v_dropped_words, v_dropped_filters, v_requested_gamas
    from universe
    cross join lateral (
      select coalesce(bool_and(source.value in (
          'product_spec', 'identity_fallback', 'name_reading'
        )), true) predicates_match
      from requested_predicates predicate
      cross join lateral (
        select public.assistant_inventory_technical_predicate_source_internal_v1(
          p_tenant_id, universe.pid, predicate.field_key,
          predicate.operator, predicate.values, universe.identity_surface,
          universe.identity_raw
        ) value
      ) source
    ) predicate_state
    where predicate_state.predicates_match
      and (
        v_inferred_categories is null
        or universe.category_id = any(v_inferred_categories)
      )
      and (
        v_query is null
        or (
          case when v_match_any then
            exists (
              select 1 from regexp_split_to_table(v_query, ' +') token
              where length(token) >= 3
                and (
                  ' ' || universe.identity_surface || ' '
                    like '% ' || token || ' %'
                  or ' ' || universe.identity_surface || ' '
                    like '% ' || public.purchase_word_stem_internal_v1(token)
                      || ' %'
                )
            )
          else
            not exists (
              select 1 from regexp_split_to_table(v_query, ' +') token
              where position(token in universe.identity_surface) = 0
                and position(
                  public.purchase_word_stem_internal_v1(token)
                  in universe.identity_surface
                ) = 0
            )
          end
        )
      );

    get diagnostics v_found = row_count;
  end loop;
end;
$function$

;

-- normalize_supply_request_items_internal_v1: la lectura del nombre cuenta como ficha en el carril de compras.
CREATE OR REPLACE FUNCTION public.normalize_supply_request_items_internal_v1(p_tenant_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_item jsonb;
  v_predicate jsonb;
  v_value jsonb;
  v_product_id uuid;
  v_product_name text;
  v_product_sku text;
  v_identity_surface text;
  v_identity_raw text;
  v_line_refs text[] := array[]::text[];
  v_predicate_fields text[];
  v_line_ref text;
  v_description text;
  v_unit text;
  v_preference text;
  v_clarification text;
  v_field text;
  v_operator text;
  v_quantity numeric;
  v_values jsonb;
  v_values_count integer;
  v_definition record;
  v_predicate_source text;
  v_normalized jsonb := '[]'::jsonb;
  v_allowed_keys constant text[] := array[
    'lineRef', 'description', 'productId', 'quantity', 'unit',
    'technicalPredicates', 'preference', 'clarification',
    'clarificationRequired'
  ];
begin
  if p_tenant_id is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 8 then
    raise exception 'Invalid supply request items' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ?& v_allowed_keys)
       or exists (
         select 1
         from jsonb_object_keys(v_item) key
         where not (key = any(v_allowed_keys))
       ) then
      raise exception 'Invalid supply request item' using errcode = '22023';
    end if;

    v_line_ref := v_item ->> 'lineRef';
    v_description := btrim(coalesce(v_item ->> 'description', ''));
    v_unit := btrim(coalesce(v_item ->> 'unit', ''));
    v_preference := nullif(btrim(coalesce(v_item ->> 'preference', '')), '');
    v_clarification :=
      nullif(btrim(coalesce(v_item ->> 'clarification', '')), '');

    if v_line_ref !~ '^line-[1-8]$'
       or v_line_ref = any(v_line_refs)
       or v_description = '' or octet_length(v_description) > 2000
       or v_unit = '' or octet_length(v_unit) > 32
       or jsonb_typeof(v_item -> 'quantity') <> 'number'
       or jsonb_typeof(v_item -> 'clarificationRequired') <> 'boolean'
       or (v_preference is not null and octet_length(v_preference) > 240)
       or (v_clarification is not null and octet_length(v_clarification) > 500)
       or (v_item -> 'preference') is null
       or jsonb_typeof(v_item -> 'preference') not in ('string', 'null')
       or (v_item -> 'clarification') is null
       or jsonb_typeof(v_item -> 'clarification') not in ('string', 'null')
       or (v_item -> 'productId') is null
       or jsonb_typeof(v_item -> 'productId') not in ('string', 'null')
       or jsonb_typeof(v_item -> 'technicalPredicates') <> 'array'
       or jsonb_array_length(v_item -> 'technicalPredicates') > 8 then
      raise exception 'Invalid supply request item' using errcode = '22023';
    end if;

    v_quantity := (v_item ->> 'quantity')::numeric;
    if v_quantity < 0.001 or v_quantity > 999999 then
      raise exception 'Invalid supply request quantity' using errcode = '22023';
    end if;

    v_product_id := null;
    v_product_name := null;
    v_product_sku := null;
    v_identity_surface := null;
    v_identity_raw := null;
    if jsonb_typeof(v_item -> 'productId') = 'string' then
      if (v_item ->> 'productId') !~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        raise exception 'Invalid catalog product' using errcode = '22023';
      end if;
      v_product_id := (v_item ->> 'productId')::uuid;
      select product.name, product.sku,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.brand, product.model, product.manufacturer,
          product.category_name, product.category
        )),
        unaccent(lower(concat_ws(' ', product.name, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category)))
      into v_product_name, v_product_sku, v_identity_surface, v_identity_raw
      from public.products product
      where product.tenant_id = p_tenant_id
        and product.id = v_product_id
        and product.is_active is true
        and not coalesce(product.is_service, false)
        and coalesce(product.product_type, 'product') <> 'service';
      if not found then
        raise exception 'Catalog product is unavailable' using errcode = '23514';
      end if;
    end if;

    if (v_item ->> 'clarificationRequired')::boolean
       and (v_clarification is null or v_product_id is not null) then
      raise exception 'Invalid blocking clarification' using errcode = '22023';
    end if;

    v_predicate_fields := array[]::text[];
    for v_predicate in
      select value from jsonb_array_elements(v_item -> 'technicalPredicates')
    loop
      if jsonb_typeof(v_predicate) <> 'object'
         or not (v_predicate ?& array['field', 'operator', 'values'])
         or exists (
           select 1 from jsonb_object_keys(v_predicate) key
           where not (key = any(array['field', 'operator', 'values']))
         )
         or coalesce(v_predicate ->> 'field', '')
              !~ '^[a-z][a-z0-9_]{1,63}$'
         or coalesce(v_predicate ->> 'operator', '') not in (
           'eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'between', 'in', 'contains'
         )
         or jsonb_typeof(v_predicate -> 'values') <> 'array' then
        raise exception 'Invalid technical predicate' using errcode = '22023';
      end if;
      v_field := v_predicate ->> 'field';
      v_operator := v_predicate ->> 'operator';
      v_values := v_predicate -> 'values';
      v_values_count := jsonb_array_length(v_predicate -> 'values');
      if v_values_count not between 1 and 10
         or v_field = any(v_predicate_fields)
         or (v_operator = 'between' and v_values_count <> 2)
         or (v_operator not in ('between', 'in')
           and v_values_count <> 1) then
        raise exception 'Invalid technical predicate values'
          using errcode = '22023';
      end if;
      for v_value in
        select value from jsonb_array_elements(v_predicate -> 'values')
      loop
        if jsonb_typeof(v_value) not in ('string', 'number', 'boolean')
           or (jsonb_typeof(v_value) = 'string'
             and octet_length(v_value #>> '{}') > 160) then
          raise exception 'Invalid technical predicate value'
            using errcode = '22023';
        end if;
      end loop;

      select definition.data_type, definition.allowed_values
      into v_definition
      from public.spec_definitions definition
      where definition.key = v_field
        and (definition.tenant_id is null
          or definition.tenant_id = p_tenant_id)
        and definition.is_filterable is true
      order by (definition.tenant_id is not null) desc
      limit 1;
      if not found then
        raise exception 'Unknown technical predicate' using errcode = '22023';
      end if;

      if (v_definition.data_type = 'number' and (
          v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'number'
          )
        ))
        or (v_definition.data_type = 'boolean' and (
          v_operator not in ('eq','neq')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'boolean'
          )
        ))
        or (v_definition.data_type in ('single_select','multi_select') and (
          v_operator not in ('eq','neq','in')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'string'
              or (
                jsonb_array_length(v_definition.allowed_values) > 0
                and not exists (
                  select 1
                  from jsonb_array_elements(v_definition.allowed_values)
                    allowed(value)
                  where public.assistant_normalize_query_internal_v1(
                    allowed.value #>> '{}'
                  ) = public.assistant_normalize_query_internal_v1(
                    requested.value #>> '{}'
                  )
                )
              )
          )
        ))
        or (v_definition.data_type = 'text' and (
          v_operator not in ('eq','neq','in','contains')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'string'
              or octet_length(requested.value #>> '{}') not between 1 and 120
          )
        ))
        or v_definition.data_type not in (
          'number','boolean','single_select','multi_select','text'
        ) then
        raise exception 'Invalid technical predicate type'
          using errcode = '22023';
      end if;

      if v_product_id is not null then
        v_predicate_source :=
          public.assistant_inventory_technical_predicate_source_internal_v1(
            p_tenant_id, v_product_id, v_field, v_operator, v_values,
            v_identity_surface, v_identity_raw
          );
        if v_predicate_source not in ('product_spec', 'identity_fallback', 'name_reading') then
          raise exception 'Catalog product does not satisfy request'
            using errcode = '23514';
        end if;
      end if;
      v_predicate_fields := array_append(v_predicate_fields, v_field);
    end loop;

    v_line_refs := array_append(v_line_refs, v_line_ref);
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'lineRef', v_line_ref,
      'description', v_description,
      'productId', v_product_id,
      'productName', v_product_name,
      'productSku', v_product_sku,
      'identityState', case when v_product_id is null then 'unresolved'
        else 'confirmed' end,
      'quantity', v_quantity,
      'unit', v_unit,
      'technicalPredicates', v_item -> 'technicalPredicates',
      'preference', v_preference,
      'clarification', v_clarification,
      'clarificationRequired',
        (v_item ->> 'clarificationRequired')::boolean
    ));
  end loop;

  return v_normalized;
end;
$function$

;
