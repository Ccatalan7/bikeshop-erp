-- Lo que la necesidad nueva y la revision del diff dejaron pendiente.
--
-- La 270 y la 280 estan aplicadas y selladas; todo esto va hacia delante.
--
--  (a) **El rotulo contradecia al boton, y sigue siendo asi en produccion.**
--      Las dos primeras filas de la necesidad de cambios traseros salieron
--      `evidenceComplete = true` y `matchState = weak` a la vez. La causa no es
--      la procedencia nueva: `identity_fallback` completaba la evidencia y
--      nunca contaba para `strong`, asi que una fila probada entera por
--      identidad curada tambien salia rotulada parcial. Los dos juicios pasan a
--      usar la misma lista, que es lo unico que impide que vuelvan a separarse.
--
--  (b) **Una sigla de dos letras es una palabra.** El puntaje ignoraba las
--      palabras de menos de tres letras, y `SS / corta` se quedaba sin su unico
--      token distintivo: dos lecturas honestas del catalogo real murieron por
--      eso. Con el piso en dos, `SS` cuenta -- y sigue exigiendo coincidencia
--      EXACTA, porque una palabra corta no tolera flexion: `SGS` no prueba `SS`
--      ni `GS`, que es justo lo que hay que distinguir.
--
--  (c) **La huella del vocabulario tiene que incluir la descripcion del
--      campo.** El lector booleano saca sus sinonimos de la cabeza de
--      `description` -- `Autosellante o anti-pinchazo: ...` --, asi que
--      cambiarla cambia lo que una cita prueba. Sin la descripcion adentro, una
--      lectura vieja seguia vigente despues de que su fundamento cambio.
--
--  (d) **La prioridad humana tiene que ser atomica, no solo estar escrita.**
--      Dos lectores concurrentes, o un guardado manual al mismo tiempo, podian
--      chocar en el indice unico o dejar un recibo colgando de un hecho que ya
--      es del mecanico. Se serializa por producto y campo con un lock de
--      transaccion, y ademas la base impide por si sola que un recibo exista
--      sobre un hecho que no sea una lectura: el candado ordena, el disparador
--      no depende de que nadie se acuerde.
--
--  (e) **El recibo queda amarrado al mismo hecho, taller y campo**, y sus dos
--      huellas dejan de poder ser nulas. Produccion no tiene ninguna lectura
--      guardada, asi que la restriccion entra sin migrar nada.

-- ---------------------------------------------------------------------------
-- (b) El puntaje cuenta las siglas cortas.
-- ---------------------------------------------------------------------------

create or replace function public.spec_label_score_internal_v1(
  p_quote_normalized text, p_label_normalized text)
returns numeric[]
language sql
immutable
as $function$
  with palabras as (
    select w from unnest(string_to_array(p_label_normalized, ' ')) as t(w)
    where length(w) >= 2
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

-- ---------------------------------------------------------------------------
-- (a) El rotulo y el boton usan la misma lista.
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
    -- **Comprobada es comprobada, y el rotulo lo dice.** La lista es la misma
    -- que usa `supply_need_evidence_is_complete_internal_v1`: mientras sean dos
    -- listas distintas, una fila puede salir completa para el boton y parcial
    -- para el texto, que es lo que estaba pasando en produccion.
    when not exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' not in (
        'product_spec', 'identity_fallback', 'name_reading')
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
-- (c) La huella incluye la descripcion, que es vocabulario del booleano.
-- ---------------------------------------------------------------------------

create or replace function public.spec_definition_vocabulary_digest_internal_v1(
  p_definition_id uuid)
returns text
language sql
stable
as $function$
  select encode(sha256(convert_to(
    coalesce((
      select d.label || E'\x1f' || d.data_type || E'\x1f' || coalesce(d.description, '')
      from public.spec_definitions d
      where d.id = p_definition_id), '') || E'\x1f' ||
    coalesce((
      select string_agg(v.label, E'\x1f' order by v.sort_order, v.id)
      from public.spec_definition_values v
      where v.spec_definition_id = p_definition_id and v.is_active is true
    ), ''), 'UTF8')), 'hex');
$function$;

-- ---------------------------------------------------------------------------
-- (e) El recibo, amarrado y sin huecos.
-- ---------------------------------------------------------------------------

-- Produccion no tiene ninguna lectura guardada; esto se comprueba antes de
-- endurecer, para no romper en silencio si alguna entrara entremedio.
do $$
begin
  if exists (
    select 1 from public.spec_fact_readings
    where definition_id is null or vocabulary_digest is null
  ) then
    raise exception 'Hay recibos sin campo o sin huella de vocabulario.';
  end if;
end $$;

alter table public.spec_fact_readings alter column definition_id set not null;
alter table public.spec_fact_readings alter column vocabulary_digest set not null;

-- El orden importa: la clave ajena cuelga del indice unico, asi que se retira
-- primero o este mismo forward no se puede volver a correr.
alter table public.spec_fact_readings
  drop constraint if exists spec_fact_readings_belongs_to_its_fact;
alter table public.spec_facts
  drop constraint if exists spec_facts_id_tenant_definition_unique;
alter table public.spec_facts
  add constraint spec_facts_id_tenant_definition_unique
  unique (id, tenant_id, spec_definition_id);
alter table public.spec_fact_readings
  add constraint spec_fact_readings_belongs_to_its_fact
  foreign key (fact_id, tenant_id, definition_id)
  references public.spec_facts (id, tenant_id, spec_definition_id)
  on delete cascade;

-- ---------------------------------------------------------------------------
-- (d) La base impide un recibo sobre un hecho que no es una lectura.
-- ---------------------------------------------------------------------------

create or replace function public.spec_fact_reading_requires_reading_internal_v1()
returns trigger
language plpgsql
as $function$
declare
  v_source text;
begin
  select f.source into v_source from public.spec_facts f where f.id = new.fact_id;
  if v_source is distinct from 'name_reading' then
    raise exception 'Un recibo de lectura sólo puede colgar de una lectura.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists spec_fact_readings_only_on_readings
  on public.spec_fact_readings;
create constraint trigger spec_fact_readings_only_on_readings
  after insert or update on public.spec_fact_readings
  deferrable initially immediate
  for each row
  execute function public.spec_fact_reading_requires_reading_internal_v1();

-- Y cuando una persona se queda con el campo, el recibo se va con la
-- procedencia. No depende de que quien escriba se acuerde de borrarlo: una
-- ruta futura que actualice `source` queda cubierta igual.
create or replace function public.spec_fact_drops_its_reading_internal_v1()
returns trigger
language plpgsql
as $function$
begin
  if new.source is distinct from 'name_reading' then
    delete from public.spec_fact_readings where fact_id = new.id;
  end if;
  return new;
end;
$function$;

drop trigger if exists spec_facts_drop_reading_on_source_change
  on public.spec_facts;
create trigger spec_facts_drop_reading_on_source_change
  after update of source on public.spec_facts
  for each row
  when (old.source is distinct from new.source)
  execute function public.spec_fact_drops_its_reading_internal_v1();

-- ---------------------------------------------------------------------------
-- (d) Y los dos que escriben toman el mismo candado, en el mismo orden.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_product_spec_reading_v1(p_product_id uuid, p_field_key text, p_value jsonb, p_quote text, p_model text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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

  -- **El candado es por PRODUCTO, no por campo.** Por campo alcanzaba para
  -- dos lectores, pero no para el guardado manual: ese empieza BORRANDO los
  -- campos que la plantilla incluye y el payload no trae --vaciar un criterio
  -- es parte de guardar-- y ese borrado ocurre antes de saber que campos va a
  -- tocar. Con candados por campo, un lector podia reinsertar justo el campo
  -- que la persona acababa de vaciar. Y dos guardados con los campos en
  -- distinto orden podian trabarse entre si. Una sola llave por producto no
  -- tiene ninguno de los dos problemas, y la ficha de un producto se escribe
  -- lo bastante poco como para que la granularidad no importe.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':spec_fact:' || p_product_id::text, 0));

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
$function$

;

revoke all on function public.record_product_spec_reading_v1(
  uuid, text, jsonb, text, text) from public;
grant execute on function public.record_product_spec_reading_v1(
  uuid, text, jsonb, text, text) to authenticated;
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

  -- **La misma llave que toma la lectura, y antes de tocar nada.** Vaciar un
  -- criterio es lo primero que hace esta función; sin el candado acá, una
  -- lectura en vuelo podía reinsertar justo el campo que la persona acababa de
  -- vaciar, y el resultado quedaba escrito por el lector aunque la persona
  -- hubiera llegado después.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant::text || ':spec_fact:' || p_product_id::text, 0));

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
