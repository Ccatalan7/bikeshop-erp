-- Deployment status: NOT DEPLOYED
-- Cambios de partes, segundo concepto: el neumático
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, «Cambios de partes: el neumático»).
--
-- Lo que la evidencia de producción (2026-09-28) cambió del pedido:
--
-- * La ficha de la bici no tenía ningún dato de neumático por rueda (0 claves
--   en 468 fichas): sólo `bikes.wheel_size`, el aro de la bici completa. Un
--   neumático no cambia el diámetro de una rueda —lo fija la llanta—: su BSD
--   (ISO 5775) tiene que calzar con ella. El dato por rueda es entonces el BSD
--   de cada rueda (`frontWheelBsdMm` / `rearWheelBsdMm`): el neumático lo
--   llena si falta, y si la bici ya dice otro es un conflicto, no un cambio.
-- * La medida no se proyecta: `tire_width_mm` del catálogo es la pulgada
--   nominal convertida (2,25″ → 57,1 mm) y difiere del ETRTO en los 7
--   neumáticos que tienen los dos (57,1 frente a 54-622; 53,3 frente a
--   52-559).
-- * Ningún dato de ficha técnica de producto está verificado (0 de 4.604
--   `spec_facts` con `confirmed`); los BSD vienen de texto de proveedor (110),
--   importación (4), investigación (4) y lectura del nombre (1). Lo que un
--   repuesto proyecta a la ficha de la bici entra **declarado** (op
--   `declare`: el valor, con origen `job_completion` y sin confirmar), y sólo
--   un dato verificado del producto se escribe confirmado (`set`). Vale
--   también para el rotor de `20260928100000`, que confirmaba diámetros leídos
--   del nombre.
-- * `bead_seat_diameter_mm` lo comparten neumático, llanta y fondo de llanta:
--   la relación dice ahora para qué familia vale cada fila (`template_key`) y
--   qué pasa si la bici ya dice otra cosa (`on_mismatch`: `change` para el
--   rotor, `conflict` para el BSD del neumático). La llanta, que sí cambia el
--   diámetro de su rueda, será otra fila.
-- * El aro de la bici refuta sólo cuando el rótulo es un solo diámetro (ISO
--   5775): 29″ y 700c son 622; 27,5″ y 650b son 584. Los demás no refutan
--   nada: 26″ son al menos seis diámetros (559, 571, 584 —el 650B se vendió
--   como «26 × 1 1/2»—, 590, 597 y 599), y 24″, 20″, 16″ y 14″ tampoco tienen
--   un conjunto que se pueda dar por completo (Sheldon Brown, «Tire Sizing»;
--   la primera versión refutaba con listas incompletas —revisión de Codex,
--   2026-09-28—). Un rótulo ilegible —«28», «27.5" - 26"», «2 9», vacío— no
--   refuta nada. La lectura es la de `canonicalBikeWheelSizeLabel`
--   (`wheel_canonical_data.dart`), que ya leía «700» como 700c.
--
-- Depende de `20260928100000`.
begin;

-- ============================================================================
-- La relación única: familia, qué hacer si la bici dice otra cosa, artículo
-- ============================================================================

alter table public.bike_fact_spec_links
  add column if not exists id uuid not null default gen_random_uuid(),
  add column if not exists template_key text,
  add column if not exists on_mismatch text not null default 'change',
  add column if not exists component_article text not null default 'el';

alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_on_mismatch_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_on_mismatch_check
  check (on_mismatch in ('change', 'conflict'));
alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_article_check;
alter table public.bike_fact_spec_links
  add constraint bike_fact_spec_links_article_check
  check (component_article in ('el', 'la'));

-- Un concepto y una posición pueden ir a la misma clave desde familias
-- distintas (el BSD del neumático y, después, el de la llanta): la clave deja
-- de ser única y la fila se identifica por su id.
alter table public.bike_fact_spec_links
  drop constraint if exists bike_fact_spec_links_bike_fact_key_key;
do $do$
begin
  if exists (
    select 1
      from pg_constraint c
     where c.conrelid = 'public.bike_fact_spec_links'::regclass
       and c.contype = 'p'
       and c.conname = 'bike_fact_spec_links_pkey'
       and array_length(c.conkey, 1) = 2
  ) then
    alter table public.bike_fact_spec_links
      drop constraint bike_fact_spec_links_pkey;
    alter table public.bike_fact_spec_links
      add constraint bike_fact_spec_links_pkey primary key (id);
  end if;
end;
$do$;
create unique index if not exists bike_fact_spec_links_concept_position_family
  on public.bike_fact_spec_links (spec_key, position, coalesce(template_key, ''));

update public.bike_fact_spec_links
   set on_mismatch = 'change',
       component_article = 'el'
 where spec_key = 'rotor_diameter_mm_value';

-- El BSD del neumático (ISO 5775) por rueda. Rango de taller: de 150 a 700
-- mm cubre de 152 (10″) a 642 (700A).
insert into public.bike_fact_spec_links (
  spec_key, position, bike_fact_key, component_label, component_article,
  unit, requires_fact_key, requires_fact_values, min_value, max_value,
  template_key, on_mismatch
) values
  ('bead_seat_diameter_mm', 'front', 'frontWheelBsdMm', 'rueda delantera',
   'la', null, null, '{}', 150, 700, 'tire', 'conflict'),
  ('bead_seat_diameter_mm', 'rear', 'rearWheelBsdMm', 'rueda trasera',
   'la', null, null, '{}', 150, 700, 'tire', 'conflict')
on conflict (spec_key, position, coalesce(template_key, '')) do update
   set bike_fact_key = excluded.bike_fact_key,
       component_label = excluded.component_label,
       component_article = excluded.component_article,
       unit = excluded.unit,
       requires_fact_key = excluded.requires_fact_key,
       requires_fact_values = excluded.requires_fact_values,
       min_value = excluded.min_value,
       max_value = excluded.max_value,
       on_mismatch = excluded.on_mismatch;

-- ============================================================================
-- ISO 5775: lo que un rótulo de aro puede medir
-- ============================================================================

-- La misma lectura que `canonicalBikeWheelSizeLabel` y la misma tabla que
-- `kIsoBsdCandidatesByWheelLabel` (`wheel_canonical_data.dart`), con una
-- gramática explícita: un número entero o decimal, espacios sólo alrededor, y
-- a lo más la pulgada; «650b»; «700», «700c» o «700"». Sólo 29″/700c y
-- 27,5″/650b refutan; cualquier otro rótulo da vacío (no se refuta sin un
-- conjunto completo).
create or replace function public.iso_bsd_candidates_for_wheel_size(p_label text)
returns integer[]
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v_text text;
  v_label text;
begin
  if p_label is null then
    return '{}'::integer[];
  end if;
  v_text := lower(regexp_replace(replace(p_label, chr(160), ' '), '^\s+|\s+$', '', 'g'));
  v_text := replace(replace(replace(replace(
    v_text, '”', '"'), '″', '"'), '''''', '"'), ',', '.');
  if v_text ~ '^650\s*b$' then
    v_label := '650b';
  elsif v_text ~ '^700\s*(c|")?$' then
    v_label := '700c';
  elsif v_text ~ '^[0-9]+(\.[0-9]+)?\s*"?$' then
    v_label := substring(v_text from '^([0-9]+(\.[0-9]+)?)') || '"';
  else
    return '{}'::integer[];
  end if;
  return case v_label
    when '27.5"' then '{584}'
    when '29"' then '{622}'
    when '700c' then '{622}'
    when '650b' then '{584}'
    else '{}'
  end::integer[];
end;
$function$;

revoke all on function public.iso_bsd_candidates_for_wheel_size(text)
  from public, anon, authenticated, service_role;

-- «622 (29″/700c)»: como lo dice el taller (`isoWheelBsdLabel`).
create or replace function public.iso_bsd_wheel_label(p_bsd numeric)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  -- Los BSD de la tabla ISO de Sheldon Brown («Tire Sizing») entre 150 y
  -- 700 mm, con el nombre que usa el taller; el mismo texto que
  -- `isoWheelBsdLabel`.
  select coalesce(p_bsd::integer::text, '?') || coalesce(' (' || case p_bsd::integer
    when 686 then '32″'
    when 642 then '28″ 700A'
    when 635 then '28″ 635'
    when 630 then '27″'
    when 622 then '29″/700c'
    when 609 then '27″ danés'
    when 599 then '26″ 599'
    when 597 then '26″ inglés'
    when 590 then '26″ 650a'
    when 584 then '27,5″/650b'
    when 583 then '700D'
    when 571 then '26″ 650c'
    when 559 then '26″'
    when 547 then '24″ 547'
    when 541 then '24″ 600A'
    when 540 then '24″ 540'
    when 534 then '24″ holandés'
    when 520 then '24″ 520'
    when 507 then '24″'
    when 501 then '22″ inglés'
    when 490 then '22″ 550A'
    when 489 then '22″ holandés'
    when 484 then '22″ 550B'
    when 457 then '22″'
    when 451 then '20″ 451'
    when 440 then '20″ 500A'
    when 438 then '20″ holandés'
    when 428 then '20″ sueco'
    when 419 then '20″ 419'
    when 406 then '20″'
    when 400 then '18″ 400'
    when 390 then '18″ 450A'
    when 369 then '17″'
    when 355 then '18″'
    when 349 then '16″ 349'
    when 340 then '16″ 400A'
    when 337 then '16″ 337'
    when 335 then '16″ 335'
    when 317 then '16″ 317'
    when 305 then '16″'
    when 298 then '14″ 298'
    when 288 then '14″ 350A'
    when 254 then '14″'
    when 252 then '12″ francés'
    when 203 then '12″'
    when 152 then '10″'
  end || ')', '');
$function$;

revoke all on function public.iso_bsd_wheel_label(numeric)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- El dato del producto: valor, familia y si está verificado
-- ============================================================================

-- El mismo lector que la app (`get_product_spec_contexts_v1`: la plantilla
-- vigente, sin campos retirados), más la familia del producto y si el hecho
-- está verificado (`spec_facts.confirmed`; hoy ninguno lo está).
create or replace function public.product_bike_fact_spec_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_spec_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
           'value', public.spec_active_product_values_internal_v1(p.id, t.id) -> p_spec_key,
           'template_key', b.template_key,
           'verified', coalesce((
             select f.confirmed
               from public.spec_facts f
               join public.spec_template_fields tf
                 on tf.spec_definition_id = f.spec_definition_id
                and tf.template_id = t.id
               join public.spec_definitions d
                 on d.id = f.spec_definition_id
              where f.tenant_id = p.tenant_id
                and f.subject_type = 'product'
                and f.subject_id = p.id
                and f.subject_scope is null
                and d.key = p_spec_key
              limit 1
           ), false))
    into v_result
    from public.products p
    join public.product_spec_bindings_internal_v1 b
      on b.product_id = p.id
    join public.spec_templates t
      on t.id = b.template_id
     and t.is_active
     and (t.tenant_id is null or t.tenant_id = p.tenant_id)
   where p.id = p_product_id
     and p.tenant_id = p_tenant_id;
  return v_result;
end;
$function$;

revoke all on function public.product_bike_fact_spec_internal(uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- El lector anterior queda como vista de éste: una sola fuente.
create or replace function public.product_bike_fact_spec_value_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_spec_key text
)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select public.product_bike_fact_spec_internal(p_tenant_id, p_product_id, p_spec_key) -> 'value';
$function$;

revoke all on function public.product_bike_fact_spec_value_internal(uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- Lo que una línea de repuesto instala en la ficha, si su marca todavía lo
-- respalda: la fila de la relación para la rueda de la línea y la familia de
-- su producto, y el valor que dice hoy su ficha técnica; más si ese dato está
-- verificado (se escribe confirmado) o sólo declarado.
create or replace function public.job_line_part_change_internal(
  p_tenant_id uuid,
  p_item_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_item public.mechanic_job_items%rowtype;
  v_link public.bike_fact_spec_links%rowtype;
  v_marked text;
  v_spec jsonb;
  v_spec_text text;
  v_found boolean := false;
begin
  select *
    into v_item
    from public.mechanic_job_items i
   where i.id = p_item_id
     and i.tenant_id = p_tenant_id;
  if not found
     or v_item.product_id is null
     or jsonb_typeof(v_item.service_configuration_data->'part_change')
        is distinct from 'object' then
    return null;
  end if;

  for v_link in
    select *
      from public.bike_fact_spec_links l
     where l.bike_fact_key = v_item.service_configuration_data->'part_change'->>'key'
       and l.position = v_item.location_key
     order by l.template_key nulls last
  loop
    v_spec := public.product_bike_fact_spec_internal(
      p_tenant_id, v_item.product_id, v_link.spec_key);
    if v_link.template_key is null
       or v_link.template_key = v_spec->>'template_key' then
      v_found := true;
      exit;
    end if;
  end loop;
  if not v_found then
    return null;
  end if;

  v_marked := v_item.service_configuration_data->'part_change'->>'value';
  v_spec_text := v_spec->'value' #>> '{}';
  -- Medidas enteras (mm): un decimal no se redondea a una medida de la ficha.
  if v_marked is null
     or v_spec_text is null
     or v_marked !~ '^[0-9]{1,4}(\.0+)?$'
     or v_spec_text !~ '^[0-9]{1,4}(\.0+)?$' then
    return null;
  end if;
  if v_marked::numeric <> v_spec_text::numeric then
    return null;
  end if;

  -- La fila que usó la línea: su regla (`on_mismatch`) y su familia deciden,
  -- no otra fila con la misma clave (revisión de Codex, 2026-09-28).
  return jsonb_build_object(
    'key', v_link.bike_fact_key,
    'value', v_spec_text::numeric::integer,
    'spec_key', v_link.spec_key,
    'position', v_link.position,
    'link_id', v_link.id,
    'on_mismatch', v_link.on_mismatch,
    'verified', coalesce((v_spec->>'verified')::boolean, false)
  );
end;
$function$;

revoke all on function public.job_line_part_change_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Lo que la bici ya dice
-- ============================================================================

-- ¿Escribió esta línea el valor que la bici tiene hoy en esa clave? Sí sólo
-- si el último recibo de esa bici que tocó la clave es de la línea, con
-- `set` o `declare` y ese valor. Un recibo que declaró lo mismo que ya decía
-- la ficha no aplicó nada y no cuenta (revisión de Codex, 2026-09-28). Los
-- recibos de una bici se escriben con la bici tomada, en orden; si dos
-- tuvieran el mismo instante, gana el de otra línea: ante la duda, el valor
-- no es de ésta.
create or replace function public.bike_fact_line_wrote_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_key text,
  p_value numeric
)
returns boolean
language sql
stable
set search_path to 'public'
as $function$
  select coalesce((
    select latest.operation_key like 'job_completion:' || p_item_id::text || ':%'
           and latest.op in ('set', 'declare')
           and jsonb_typeof(latest.to_value) = 'number'
           and (latest.to_value #>> '{}')::numeric = p_value
      from (
        select p.operation_key, e->>'op' as op, e->'to' as to_value
          from public.bike_technical_fact_patches p
         cross join lateral jsonb_array_elements(
                 case when jsonb_typeof(p.applied) = 'array'
                      then p.applied else '[]'::jsonb end) e
         where p.tenant_id = p_tenant_id
           and p.bike_id = p_bike_id
           and e->>'key' = p_key
         order by p.completed_at desc,
                  (p.operation_key like 'job_completion:' || p_item_id::text || ':%')
         limit 1
      ) latest
  ), false);
$function$;

revoke all on function public.bike_fact_line_wrote_internal(uuid, uuid, uuid, text, numeric)
  from public, anon, authenticated, service_role;

-- Con qué choca una pieza que tiene que calzar con lo que la rueda ya es
-- (la fila que usó la línea dice `on_mismatch = 'conflict'`): lo que la ficha
-- dice en esa clave —salvo que lo haya escrito esta misma línea y nadie lo
-- haya tocado después, que se está corrigiendo—, o, si la ficha
-- no lo dice, el aro de la bici leído con ISO 5775. Nulo si calza o si no se
-- puede refutar. Una sola regla para el aplicador y el parche, siempre con la
-- bici y la ficha ya tomadas.
create or replace function public.bike_fact_part_conflict_internal(
  p_tenant_id uuid,
  p_item_id uuid,
  p_bike_id uuid,
  p_key text,
  p_value jsonb,
  p_values jsonb,
  p_sources jsonb,
  p_wheel_size text
)
returns jsonb
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_value numeric;
  v_current_text text;
  v_current numeric;
  v_candidates integer[];
  v_part jsonb;
begin
  v_part := public.job_line_part_change_internal(p_tenant_id, p_item_id);
  if v_part is null
     or v_part->>'key' is distinct from p_key
     or v_part->>'on_mismatch' is distinct from 'conflict' then
    return null;
  end if;
  if p_value is null or jsonb_typeof(p_value) <> 'number' then
    return null;
  end if;
  v_value := (p_value #>> '{}')::numeric;

  v_current_text := coalesce(p_values, '{}'::jsonb)->>p_key;
  if v_current_text ~ '^[0-9]{1,4}(\.0+)?$' then
    v_current := v_current_text::numeric;
    if v_current = v_value then
      return null;
    end if;
    -- Lo escribió esta misma línea en esta bici y sigue siendo suyo: se está
    -- corrigiendo. «Lo escribió» es el último recibo de esta bici que tocó la
    -- clave, con lo que de verdad aplicó: un recibo que declaró lo mismo que
    -- ya decía la ficha no escribió nada y no hace suyo el valor de otra
    -- línea (revisión de Codex, 2026-09-28). Si el mecánico lo volvió a
    -- elegir en la ficha (fuente `mechanic`), aunque sea el mismo número, ya
    -- es una medida suya.
    if coalesce(p_sources, '{}'::jsonb)->>p_key is distinct from 'job_completion'
       or not public.bike_fact_line_wrote_internal(
         p_tenant_id, p_item_id, p_bike_id, p_key, v_current) then
      return jsonb_build_object(
        'requires_key', p_key,
        'requires_value', v_current::integer::text
      );
    end if;
  end if;

  if p_key in ('frontWheelBsdMm', 'rearWheelBsdMm') then
    v_candidates := public.iso_bsd_candidates_for_wheel_size(p_wheel_size);
    if cardinality(v_candidates) > 0
       and not (v_value::integer = any (v_candidates)) then
      return jsonb_build_object(
        'requires_key', 'bikes.wheel_size',
        'requires_value', btrim(p_wheel_size)
      );
    end if;
  end if;
  return null;
end;
$function$;

revoke all on function public.bike_fact_part_conflict_internal(uuid, uuid, uuid, text, jsonb, jsonb, jsonb, text)
  from public, anon, authenticated, service_role;

-- Lo que cada línea de un trabajo escribió y la ficha todavía dice como
-- suyo: `{línea: {key, value}}`. El formulario lo lee para decir «Corrige la
-- ficha» sólo cuando el servidor la dejará corregir; con la marca guardada
-- adivinaba mal cuando dos trabajos instalaron la misma medida (revisión de
-- Codex, 2026-09-28). Sólo lectura, del taller del trabajo.
create or replace function public.job_part_change_writers_v1(p_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_item record;
  v_bike_id uuid;
  v_key text;
  v_current text;
  v_result jsonb := '{}'::jsonb;
begin
  if p_job_id is null then
    raise exception 'El trabajo es obligatorio.' using errcode = '22004';
  end if;
  select job.tenant_id
    into v_tenant_id
    from public.mechanic_jobs job
   where job.id = p_job_id;
  if not found then
    raise exception 'Trabajo no encontrado.' using errcode = 'P0002';
  end if;
  perform public.assert_workshop_rpc_tenant(v_tenant_id);

  for v_item in
    select i.id, i.service_configuration_data->'part_change'->>'key' as key
      from public.mechanic_job_items i
     where i.job_id = p_job_id
       and i.tenant_id = v_tenant_id
       and jsonb_typeof(i.service_configuration_data->'part_change') = 'object'
  loop
    v_key := v_item.key;
    v_bike_id := public.job_line_bike_internal(v_tenant_id, v_item.id);
    if v_key is null or v_bike_id is null then
      continue;
    end if;
    select bp.technical_profile->'values'->>v_key
      into v_current
      from public.bike_profiles bp
     where bp.bike_id = v_bike_id
       and bp.tenant_id = v_tenant_id
       and bp.technical_profile->'sources'->>v_key = 'job_completion';
    if v_current ~ '^[0-9]{1,4}(\.0+)?$'
       and public.bike_fact_line_wrote_internal(
             v_tenant_id, v_item.id, v_bike_id, v_key, v_current::numeric) then
      v_result := v_result || jsonb_build_object(
        v_item.id::text,
        jsonb_build_object('key', v_key, 'value', v_current::numeric::integer));
    end if;
  end loop;
  return v_result;
end;
$function$;

revoke all on function public.job_part_change_writers_v1(uuid)
  from public, anon, service_role;
grant execute on function public.job_part_change_writers_v1(uuid) to authenticated;

-- Lo que la ficha dice y con lo que la pieza no calza, como lo dice el taller:
-- «tipo de freno «Llanta (rim)»», «la rueda trasera es 584 (27,5″/650b)»,
-- «aro 29"».
create or replace function public.bike_fact_requirement_text(
  p_requires_key text,
  p_requires_value text
)
returns text
language sql
stable
set search_path to 'public'
as $function$
  select case
    when p_requires_key = 'brakeType' then
      'tipo de freno «' || public.bike_fact_requirement_label(p_requires_value) || '»'
    when p_requires_key = 'bikes.wheel_size' then
      'aro ' || coalesce(p_requires_value, '?')
    else coalesce(
      (select l.component_article || ' ' || l.component_label || ' es '
                || case
                     when p_requires_key in ('frontWheelBsdMm', 'rearWheelBsdMm')
                       then public.iso_bsd_wheel_label(p_requires_value::numeric)
                     else coalesce(p_requires_value, '?') || coalesce(' ' || l.unit, '')
                   end
         from public.bike_fact_spec_links l
        where l.bike_fact_key = p_requires_key
        limit 1),
      p_requires_key || ' = ' || coalesce(p_requires_value, '?'))
  end;
$function$;

revoke all on function public.bike_fact_requirement_text(text, text)
  from public, anon, authenticated, service_role;

-- Qué hacer cuando no calza.
create or replace function public.bike_fact_requirement_advice(p_requires_key text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select case p_requires_key
    when 'brakeType' then
      'Si la bici lleva freno de disco, corrige el tipo de freno en su ficha '
      || 'y guarda el trabajo; si no, quita la línea.'
    else
      'Revisa la medida del neumático y la de esa rueda: si el neumático sí '
      || 'va ahí, corrige la ficha de la bici y guarda el trabajo; si no, '
      || 'cambia la línea.'
  end;
$function$;

revoke all on function public.bike_fact_requirement_advice(text)
  from public, anon, authenticated, service_role;

-- «36H en la rueda delantera», «180 mm en el rotor trasero», «622 (29″/700c)
-- en la rueda trasera»: como lo dice el taller.
create or replace function public.installed_bike_fact_label(p_key text, p_value jsonb)
returns text
language sql
stable
set search_path to 'public'
as $function$
  select case
    when p_key in ('frontSpokeHoles', 'rearSpokeHoles') then
      coalesce(p_value #>> '{}', '?') || 'H en la rueda '
        || case p_key when 'frontSpokeHoles' then 'delantera' else 'trasera' end
    else coalesce(
      (select case
                when p_key in ('frontWheelBsdMm', 'rearWheelBsdMm')
                     and (p_value #>> '{}') ~ '^[0-9]{1,4}(\.0+)?$'
                  then public.iso_bsd_wheel_label((p_value #>> '{}')::numeric)
                else coalesce(p_value #>> '{}', '?') || coalesce(' ' || l.unit, '')
              end
              || ' en ' || l.component_article || ' ' || l.component_label
         from public.bike_fact_spec_links l
        where l.bike_fact_key = p_key
        limit 1),
      coalesce(p_key, '?') || ' = ' || coalesce(p_value #>> '{}', '?'))
  end;
$function$;

revoke all on function public.installed_bike_fact_label(text, jsonb)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- Aplicar lo instalado: declarado o confirmado, y lo que ya dice la bici
-- ============================================================================

create or replace function public.apply_job_installed_bike_facts_internal(
  p_tenant_id uuid,
  p_job_id uuid,
  p_notices_required boolean default false
)
returns jsonb
language plpgsql
set search_path to 'public'
as $function$
declare
  v_item record;
  v_position text;
  v_holes_text text;
  v_value integer;
  v_key text;
  v_op text;
  v_link public.bike_fact_spec_links%rowtype;
  v_verified jsonb;
  v_misfit text;
  v_requires jsonb;
  v_wheel_size text;
  v_profile_values jsonb;
  v_profile_sources jsonb;
  v_bike_id uuid;
  v_facts_suffix text;
  v_latest integer;
  v_latest_suffix text;
  v_operation_key text;
  v_current jsonb;
  v_current_confirmed boolean;
  v_latest_bike_id uuid;
  v_claims jsonb := '[]'::jsonb;
  v_prior record;
  v_receipt jsonb;
  v_applied jsonb := '[]'::jsonb;
  v_problems jsonb := '[]'::jsonb;
begin
  for v_item in
    select i.id,
           i.product_name,
           i.location_key,
           i.job_bike_id,
           i.service_configuration_data as data,
           jb.bike_id as line_bike_id
      from public.mechanic_job_items i
      left join public.mechanic_job_bikes jb
        on jb.id = i.job_bike_id
       and jb.tenant_id = i.tenant_id
     where i.job_id = p_job_id
       and i.tenant_id = p_tenant_id
       and (
         i.service_configuration_data ? 'hole_count'
         or i.service_configuration_data ? 'part_change'
       )
     -- Por bici, en el mismo orden en todo trabajo: dos trabajos con las
     -- mismas bicis no se toman una cada uno.
     order by jb.bike_id nulls last, i.created_at, i.id
  loop
    v_link := null;
    -- Una línea instala una sola cosa: perforaciones (un servicio) o un
    -- repuesto. Con las dos, se informa y no se escribe ninguna.
    if v_item.data ? 'hole_count' and v_item.data ? 'part_change' then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'reason', 'mixed_change'
      ));
      continue;
    end if;
    if v_item.data ? 'hole_count' then
      -- La misma regla que `serviceWheelPositions` + `wheelInstalledFacts`:
      -- una sola rueda y un número de perforaciones. «Ambas» no instala: el
      -- asistente ya le dijo al mecánico que la ficha no cambia. Lo demás que
      -- no se puede leer se informa, no se salta.
      v_position := coalesce(
        nullif(v_item.location_key, 'none'),
        v_item.data->>'which_wheel'
      );
      v_holes_text := v_item.data->>'hole_count';
      if v_position = 'both' then
        continue;
      end if;
      if v_position is null or v_position not in ('front', 'rear') then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'value', v_holes_text,
          'reason', 'no_wheel'
        ));
        continue;
      end if;
      if v_holes_text is null or v_holes_text !~ '^[1-9][0-9]{0,2}$' then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'value', v_holes_text,
          'reason', 'invalid_value'
        ));
        continue;
      end if;
      v_value := v_holes_text::integer;
      v_key := case v_position
        when 'front' then 'frontSpokeHoles'
        else 'rearSpokeHoles'
      end;
      -- Las perforaciones las contó el mecánico en el asistente: confirmadas.
      v_op := 'set';
    else
      -- Un repuesto con marca: lo que el mecánico vio al elegir la rueda, si
      -- todavía calza con el repuesto, la rueda y la ficha técnica del
      -- producto. Si no, se informa y no se escribe nada.
      v_verified := public.job_line_part_change_internal(p_tenant_id, v_item.id);
      if v_verified is null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'key', case
            when jsonb_typeof(v_item.data->'part_change'->'key') = 'string'
              then v_item.data->'part_change'->>'key'
          end,
          'value', v_item.data->'part_change'->'value',
          'reason', 'stale_change'
        ));
        continue;
      end if;
      v_key := v_verified->>'key';
      v_value := (v_verified->>'value')::integer;
      select *
        into v_link
        from public.bike_fact_spec_links l
       where l.id = (v_verified->>'link_id')::uuid;
      -- Lo que dice la ficha técnica del repuesto entra declarado; sólo un
      -- dato verificado del producto se escribe confirmado (20260928110000).
      v_op := case
        when coalesce((v_verified->>'verified')::boolean, false) then 'set'
        else 'declare'
      end;
    end if;

    -- La bici de la línea, con la misma regla que el parche: una línea de
    -- General es de la única bici del trabajo (o de la bici del trabajo, si no
    -- tiene filas de bicis).
    v_bike_id := public.job_line_bike_internal(p_tenant_id, v_item.id);
    if v_bike_id is null then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'key', v_key,
        'value', v_value,
        'reason', 'line_without_bike'
      ));
      continue;
    end if;

    -- Rangos de taller, los mismos del parche (el de un repuesto, el de su
    -- relación): fuera de ellos es un error de tipeo en la línea o en la
    -- ficha técnica del producto.
    if not (case
      when v_key in ('frontSpokeHoles', 'rearSpokeHoles')
        then v_value between 12 and 48
      when v_link.bike_fact_key is not null
        then v_value between v_link.min_value and v_link.max_value
      else false
    end) then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'bike_id', v_bike_id,
        'key', v_key,
        'value', v_value,
        'reason', 'out_of_range'
      ));
      continue;
    end if;

    -- Lo que esta línea dice hoy que instaló: con esto se reconoce abajo lo
    -- que escribió antes y ya no respalda.
    v_claims := v_claims || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id,
      'bike_id', v_bike_id,
      'key', v_key,
      'value', v_value
    ));

    v_facts_suffix := v_key || '=' || v_value::text;
    select parts[1]::integer, parts[2], receipt_bike_id
      into v_latest, v_latest_suffix, v_latest_bike_id
      from (
        select regexp_match(
                 p.operation_key,
                 '^job_completion:[^:]+:([0-9]+):(.*)$'
               ) as parts,
               p.bike_id as receipt_bike_id
          from public.bike_technical_fact_patches p
         where p.tenant_id = p_tenant_id
           and p.operation_key like 'job_completion:' || v_item.id::text || ':%'
      ) receipts
     where parts is not null
     order by parts[1]::integer desc
     limit 1;

    -- Ya escrito en esta bici, o alguien corrigió la ficha después: no se le
    -- pisa. Si la línea pasó a otra bici, esa otra no lo tiene todavía; lo
    -- que quedó en la primera no se deshace solo.
    if v_latest_suffix is not distinct from v_facts_suffix
       and v_latest_bike_id is not distinct from v_bike_id then
      continue;
    end if;
    v_operation_key := 'job_completion:' || v_item.id::text || ':'
      || (coalesce(v_latest, 0) + 1)::text || ':' || v_facts_suffix;

    begin
      -- Lo instalado vale aunque la ficha dijera otra cosa: se toma la bici y
      -- su ficha antes de leer el valor actual, para que el parche compare con
      -- lo que de verdad hay.
      v_wheel_size := null;
      select b.wheel_size
        into v_wheel_size
        from public.bikes b
       where b.id = v_bike_id
         and b.tenant_id = p_tenant_id
       for update;
      v_current := null;
      v_current_confirmed := false;
      v_misfit := null;
      v_profile_values := null;
      v_profile_sources := null;
      select bp.technical_profile->'values'->v_key,
             coalesce(bp.technical_profile->'confirmed'->>v_key, 'false') = 'true',
             public.bike_fact_part_misfit_internal(
               v_key,
               coalesce(bp.technical_profile->'values', '{}'::jsonb),
               coalesce(bp.technical_profile->'confirmed', '{}'::jsonb)),
             coalesce(bp.technical_profile->'values', '{}'::jsonb),
             coalesce(bp.technical_profile->'sources', '{}'::jsonb)
        into v_current, v_current_confirmed, v_misfit, v_profile_values,
             v_profile_sources
        from public.bike_profiles bp
       where bp.bike_id = v_bike_id
         and bp.tenant_id = p_tenant_id
       for update;

      -- La pieza tiene que calzar con la bici real, mirada con la ficha ya
      -- tomada: lo que su relación pide (un rotor, freno de disco), y lo que
      -- la rueda ya es (un neumático, su BSD o el aro de la bici leído con
      -- ISO 5775). Sin confirmar no se refuta lo que pide; un BSD distinto sí,
      -- venga de donde venga, salvo que lo haya escrito esta misma línea y
      -- siga siendo suyo.
      v_requires := case
        when v_misfit is not null then jsonb_build_object(
          'requires_key', v_link.requires_fact_key,
          'requires_value', v_misfit)
        else public.bike_fact_part_conflict_internal(
          p_tenant_id, v_item.id, v_bike_id, v_key, to_jsonb(v_value),
          coalesce(v_profile_values, '{}'::jsonb),
          coalesce(v_profile_sources, '{}'::jsonb), v_wheel_size)
      end;
      if v_requires is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'bike_id', v_bike_id,
          'key', v_key,
          'value', v_value,
          'reason', 'incompatible',
          'requires_key', v_requires->>'requires_key',
          'requires_value', v_requires->>'requires_value'
        ));
        perform public.record_installed_bike_fact_notice(
          p_tenant_id, v_bike_id, p_job_id,
          'incompatible:' || v_item.id::text || ':' || v_key || '='
            || v_value::text || ':' || (v_requires->>'requires_value'),
          'installed_fact_incompatible',
          'Aviso: lo instalado no calza con la ficha',
          format(
            '«%s» dice %s, pero la ficha de la bici dice %s: la ficha no '
            'cambió. %s',
            coalesce(v_item.product_name, 'Una línea'),
            public.installed_bike_fact_label(v_key, to_jsonb(v_value)),
            public.bike_fact_requirement_text(
              v_requires->>'requires_key', v_requires->>'requires_value'),
            public.bike_fact_requirement_advice(v_requires->>'requires_key')),
          jsonb_build_object(
            'item_id', v_item.id,
            'key', v_key,
            'value', v_value,
            'requires_key', v_requires->>'requires_key',
            'requires_value', v_requires->>'requires_value'),
          p_notices_required);
        continue;
      end if;

      v_receipt := public.patch_bike_technical_facts_v1(
        v_operation_key,
        v_bike_id,
        p_job_id,
        'job_completion',
        jsonb_build_array(jsonb_build_object(
          'key', v_key,
          'op', v_op,
          'value', v_value,
          'expected', coalesce(v_current, 'null'::jsonb),
          'expected_confirmed', coalesce(v_current_confirmed, false)
        ))
      );
      v_applied := v_applied || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'bike_id', v_bike_id,
        'key', v_key,
        'value', v_value,
        'op', v_op,
        'previous', v_current,
        'operation_key', v_operation_key,
        'changed', jsonb_array_length(coalesce(v_receipt->'applied', '[]'::jsonb)) > 0
      ));
    exception
      when others then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object(
          'item_id', v_item.id,
          'item_name', v_item.product_name,
          'bike_id', v_bike_id,
          'key', v_key,
          'value', v_value,
          'reason', 'rejected',
          'code', sqlstate,
          'message', sqlerrm
        ));
        -- Queda pendiente: se reintenta con la misma llave la próxima vez, y
        -- mientras tanto la bici lo dice en su historia.
        perform public.record_installed_bike_fact_notice(
          p_tenant_id, v_bike_id, p_job_id,
          'pending:' || v_operation_key,
          'installed_fact_pending',
          'Pendiente: la ficha no tomó lo instalado',
          format(
            'La ficha no tomó %s de «%s» (%s). Se reintenta al guardar el '
            'trabajo o volver a cambiar su estado.',
            public.installed_bike_fact_label(v_key, to_jsonb(v_value)),
            coalesce(v_item.product_name, 'una línea'),
            sqlerrm),
          jsonb_build_object(
            'operation_key', v_operation_key,
            'item_id', v_item.id,
            'key', v_key,
            'value', v_value,
            'code', sqlstate),
          p_notices_required);
    end;
  end loop;

  -- Lo que una línea de este trabajo escribió y ya no respalda: pasó a otra
  -- bici o a la otra rueda, cambió de servicio o de repuesto, o se borró. Se
  -- toma lo último que cada línea escribió en cada bici y clave; si la ficha
  -- todavía lo dice con el origen de la línea (`job_completion`) y ningún
  -- recibo posterior escribió esa clave en esa bici, se informa para que el
  -- operador la corrija o la confirme. Confirmarla es elegir el dato en su
  -- campo de la ficha, que deja el origen `mechanic`; guardar la ficha por
  -- otro campo no la revisa (el formulario conserva el origen de lo que no se
  -- tocó).
  for v_prior in
    select distinct on (p.bike_id, fact->>'key', split_part(p.operation_key, ':', 2))
           split_part(p.operation_key, ':', 2) as item_id,
           p.bike_id,
           p.operation_key,
           p.completed_at,
           fact->>'key' as key,
           fact->'to' as written,
           fact->'from' as previous,
           fact->>'op' as op,
           nullif(btrim(concat_ws(' ', b.brand, b.model)), '') as bike_label,
           i.product_name as item_name
      from public.bike_technical_fact_patches p
      cross join lateral jsonb_array_elements(coalesce(p.applied, '[]'::jsonb)) fact
      join public.bikes b
        on b.id = p.bike_id
       and b.tenant_id = p.tenant_id
      left join public.mechanic_job_items i
        on i.id::text = split_part(p.operation_key, ':', 2)
       and i.tenant_id = p.tenant_id
     where p.tenant_id = p_tenant_id
       and p.job_id = p_job_id
       and p.source = 'job_completion'
       and p.operation_key ~ '^job_completion:[^:]+:[0-9]+:'
     order by p.bike_id,
              fact->>'key',
              split_part(p.operation_key, ':', 2),
              split_part(p.operation_key, ':', 3)::integer desc
  loop
    if v_claims @> jsonb_build_array(jsonb_build_object(
         'item_id', v_prior.item_id,
         'bike_id', v_prior.bike_id,
         'key', v_prior.key,
         'value', v_prior.written
       )) then
      continue;
    end if;
    if not exists (
         select 1
           from public.bike_profiles bp
          where bp.bike_id = v_prior.bike_id
            and bp.tenant_id = p_tenant_id
            and bp.technical_profile->'values'->v_prior.key = v_prior.written
            and bp.technical_profile->'sources'->>v_prior.key = 'job_completion'
       ) then
      continue;
    end if;
    if exists (
         select 1
           from public.bike_technical_fact_patches later
          where later.tenant_id = p_tenant_id
            and later.bike_id = v_prior.bike_id
            and later.completed_at > v_prior.completed_at
            and later.operation_key <> v_prior.operation_key
            and (
              later.applied @> jsonb_build_array(
                jsonb_build_object('key', v_prior.key))
              or (
                later.source = 'job_completion'
                and split_part(later.operation_key, ':', 4)
                    ~ ('(^|,)' || v_prior.key || '=')
              )
            )
       ) then
      continue;
    end if;
    v_problems := v_problems || jsonb_build_array(jsonb_build_object(
      'item_id', v_prior.item_id,
      'item_name', v_prior.item_name,
      'bike_id', v_prior.bike_id,
      'bike_label', v_prior.bike_label,
      'key', v_prior.key,
      'value', v_prior.written,
      'previous', v_prior.previous,
      'op', v_prior.op,
      'reason', 'no_longer_installed'
    ));
    perform public.record_installed_bike_fact_notice(
      p_tenant_id, v_prior.bike_id, p_job_id,
      'unsupported:' || v_prior.operation_key || ':' || v_prior.key,
      'installed_fact_unsupported',
      'Aviso: la ficha dice algo que el trabajo ya no respalda',
      format(
        'La ficha dice %s por «%s», que ya no dice haberlo instalado en esta '
        'bici (%s). %s, corrige la ficha; si sí, vuelve a elegir el dato en su '
        'campo para confirmarlo.',
        public.installed_bike_fact_label(v_prior.key, v_prior.written),
        coalesce(v_prior.item_name, 'una línea que ya no está'),
        case
          when v_prior.previous is null or v_prior.previous = 'null'::jsonb
            then 'antes no tenía el dato'
          else 'antes: '
            || public.installed_bike_fact_label(v_prior.key, v_prior.previous)
        end,
        case
          when v_prior.key in ('frontSpokeHoles', 'rearSpokeHoles')
            then 'Si esa rueda no se armó'
          else 'Si esa pieza no se instaló'
        end),
      jsonb_build_object(
        'operation_key', v_prior.operation_key,
        'item_id', v_prior.item_id,
        'key', v_prior.key,
        'value', v_prior.written,
        'previous', v_prior.previous),
      p_notices_required);
  end loop;

  return jsonb_build_object('applied', v_applied, 'problems', v_problems);
end;
$function$;

-- Sólo la llaman los comandos del servidor, que ya comprobaron el taller.
revoke all on function public.apply_job_installed_bike_facts_internal(uuid, uuid, boolean)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- El parche: `declare`, el BSD por rueda y lo que la rueda ya es
-- ============================================================================

-- Se inserta sobre la definición vigente (la de 20260928100000) y es
-- reejecutable: anclas exactas, cada una una sola vez.
do $do$
declare
  v_fn regprocedure :=
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure;
  v_def text;
  v_anchors text[] := array[
$a$    -- Lo instalado cambia la ficha; no sugiere ni borra.
    if p_source = 'job_completion' and v_op <> 'set' then
      raise exception 'A finished job only sets installed bicycle facts';
    end if;
$a$,
$a$        'bbShellWidthMm', 'bbShellDiameterMm', 'frontSpokeHoles',
        'rearSpokeHoles'
      ) then 'number'
$a$,
$a$    if v_op in ('set', 'suggest') then
      if v_op = 'suggest' and v_kind = 'wheel_size' then
$a$,
$a$          when 'rearRotorSizeMm' then v_number = trunc(v_number) and v_number between 100 and 260
$a$,
$a$      raise exception 'Bicycle fact op must be set, suggest or remove';
$a$,
$a$          and v_item.service_configuration_data->>'hole_count'
              = v_fact->>'value'
        )
        or public.job_line_part_change_internal(v_tenant_id, v_item.id)
           @> jsonb_build_object('key', v_fact->>'key', 'value', v_fact->'value')
      ) is not true then
$a$,
$a$      v_misfit_value := public.bike_fact_part_misfit_internal(
        v_fact->>'key', v_values, v_confirmed);
      if v_misfit_value is not null then
        raise exception 'Installed part % does not fit the bicycle (% is %)',
          v_fact->>'key',
          (select l.requires_fact_key
             from public.bike_fact_spec_links l
            where l.bike_fact_key = v_fact->>'key'),
          v_misfit_value
          using errcode = '23514';
      end if;
$a$,
$a$      continue;
    end if;

    if v_op = 'remove' and v_current = 'null'::jsonb then
$a$,
$a$    elsif v_op = 'set' then
      v_values := v_values || jsonb_build_object(v_key, v_value);
      v_sources := v_sources || jsonb_build_object(v_key, v_fact_source);
      v_confirmed := v_confirmed || jsonb_build_object(v_key, true);
      v_technical_changed := true;
    else
$a$,
$a$      'to', case when v_op = 'set' then v_value else 'null'::jsonb end
$a$,
$a$  v_confirmed_any := jsonb_path_exists(v_applied, '$[*] ? (@.op != "suggest")');
$a$
  ];
  v_blocks text[] := array[
$a$    -- Lo instalado cambia la ficha; no sugiere ni borra. Lo que viene de la
    -- ficha técnica de un repuesto sin verificar entra declarado: el valor,
    -- sin confirmar (20260928110000).
    if p_source = 'job_completion' and v_op not in ('set', 'declare') then
      raise exception 'A finished job only sets or declares installed bicycle facts';
    end if;
    if v_op = 'declare' and p_source <> 'job_completion' then
      raise exception 'Only a finished job declares installed bicycle facts';
    end if;
$a$,
$a$        'bbShellWidthMm', 'bbShellDiameterMm', 'frontSpokeHoles',
        'rearSpokeHoles', 'frontWheelBsdMm', 'rearWheelBsdMm'
      ) then 'number'
$a$,
$a$    if v_op in ('set', 'suggest', 'declare') then
      if v_op = 'suggest' and v_kind = 'wheel_size' then
$a$,
$a$          when 'rearRotorSizeMm' then v_number = trunc(v_number) and v_number between 100 and 260
          -- BSD de cada rueda (ISO 5775), de 152 (10″) a 642 (700A).
          when 'frontWheelBsdMm' then v_number = trunc(v_number) and v_number between 150 and 700
          when 'rearWheelBsdMm' then v_number = trunc(v_number) and v_number between 150 and 700
$a$,
$a$      raise exception 'Bicycle fact op must be set, suggest, declare or remove';
$a$,
$a$          and v_item.service_configuration_data->>'hole_count'
              = v_fact->>'value'
          -- Las perforaciones las contó el mecánico: se confirman.
          and v_fact->>'op' = 'set'
        )
        -- Un repuesto: lo que su ficha técnica dice sin verificar entra
        -- declarado; sólo un dato verificado se confirma (20260928110000).
        or (
          public.job_line_part_change_internal(v_tenant_id, v_item.id)
            @> jsonb_build_object('key', v_fact->>'key', 'value', v_fact->'value')
          and v_fact->>'op' = case
            when (public.job_line_part_change_internal(v_tenant_id, v_item.id)
                  ->> 'verified')::boolean then 'set'
            else 'declare'
          end
        )
      ) is not true then
$a$,
$a$      v_misfit_value := public.bike_fact_part_misfit_internal(
        v_fact->>'key', v_values, v_confirmed);
      v_misfit_key := (
        select l.requires_fact_key
          from public.bike_fact_spec_links l
         where l.bike_fact_key = v_fact->>'key'
           and l.requires_fact_key is not null
         limit 1);
      -- Y lo que la rueda ya es: el BSD que dice la ficha o el aro de la
      -- bici leído con ISO 5775 (20260928110000).
      if v_misfit_value is null then
        v_conflict := public.bike_fact_part_conflict_internal(
          v_tenant_id, v_item_id, v_bike.id, v_fact->>'key', v_fact->'value',
          v_values, v_sources, v_bike.wheel_size);
        v_misfit_value := v_conflict->>'requires_value';
        v_misfit_key := v_conflict->>'requires_key';
      end if;
      if v_misfit_value is not null then
        raise exception 'Installed part % does not fit the bicycle (% is %)',
          v_fact->>'key', v_misfit_key, v_misfit_value
          using errcode = '23514';
      end if;
$a$,
$a$      continue;
    end if;

    -- Lo declarado que ya dice lo mismo no cambia nada: ni confirma ni le
    -- quita la confirmación a lo que el mecánico confirmó (20260928110000).
    if v_op = 'declare' and v_current = v_value then
      continue;
    end if;

    if v_op = 'remove' and v_current = 'null'::jsonb then
$a$,
$a$    elsif v_op = 'set' then
      v_values := v_values || jsonb_build_object(v_key, v_value);
      v_sources := v_sources || jsonb_build_object(v_key, v_fact_source);
      v_confirmed := v_confirmed || jsonb_build_object(v_key, true);
      v_technical_changed := true;
    elsif v_op = 'declare' then
      -- Declarado: el valor, con su origen, sin confirmar.
      v_values := v_values || jsonb_build_object(v_key, v_value);
      v_sources := v_sources || jsonb_build_object(v_key, v_fact_source);
      v_confirmed := v_confirmed - v_key;
      v_technical_changed := true;
    else
$a$,
$a$      'to', case when v_op in ('set', 'declare') then v_value else 'null'::jsonb end
$a$,
$a$  v_confirmed_any := jsonb_path_exists(
    v_applied, '$[*] ? (@.op != "suggest" && @.op != "declare")');
$a$
  ];
  i integer;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('Lo declarado que ya dice lo mismo no cambia nada' in v_def) > 0 then
    return;
  end if;
  for i in 1 .. array_length(v_anchors, 1) loop
    if (length(v_def) - length(replace(v_def, v_anchors[i], ''))) / length(v_anchors[i]) <> 1 then
      raise exception 'patch_bike_technical_facts_v1 no tiene el ancla % esperada', i;
    end if;
  end loop;
  for i in 1 .. array_length(v_anchors, 1) loop
    v_def := replace(v_def, v_anchors[i], v_blocks[i]);
  end loop;
  -- Las variables nuevas.
  v_def := replace(v_def,
    E'  v_misfit_value text;\nbegin\n',
    E'  v_misfit_value text;\n  v_misfit_key text;\n  v_conflict jsonb;\nbegin\n');
  execute v_def;
end;
$do$;

-- ============================================================================
-- El disparador de líneas: el texto de lo que no calza
-- ============================================================================

do $do$
declare
  v_fn regprocedure :=
    'public.apply_installed_bike_facts_on_job_line_change()'::regprocedure;
  v_def text;
  v_anchor text := $a$      when 'incompatible' then format(
        '«%s» no se guardó: %s no calza con la ficha de la bici (tipo de '
        'freno «%s»). En un trabajo terminado la línea y la ficha se guardan '
        'juntas: corrige la ficha o la línea.',
        v_line_name, v_fact,
        public.bike_fact_requirement_label(v_problem->>'requires_value'))
$a$;
  v_block text := $a$      when 'incompatible' then format(
        '«%s» no se guardó: %s no calza con la ficha de la bici (%s). En un '
        'trabajo terminado la línea y la ficha se guardan juntas: corrige la '
        'ficha o la línea.',
        v_line_name, v_fact,
        public.bike_fact_requirement_text(
          v_problem->>'requires_key', v_problem->>'requires_value'))
$a$;
begin
  v_def := pg_get_functiondef(v_fn);
  if position('bike_fact_requirement_text' in v_def) > 0 then
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'apply_installed_bike_facts_on_job_line_change no tiene el texto esperado';
  end if;
  execute replace(v_def, v_anchor, v_block);
end;
$do$;

commit;
