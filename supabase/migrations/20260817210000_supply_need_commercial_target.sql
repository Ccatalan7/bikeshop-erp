-- Preferencia comercial tipada de una necesidad, en su propio flujo.
--
-- **Lo que hoy existe y no sirve.** `constraints` guarda una entrada
-- `commercial_preference` cuyo `value` es **texto libre** de hasta 240 bytes.
-- Nadie la lee, nada la valida y no empuja ningún ranking. Y `p_gama` del
-- ranking sólo lo alimenta un selector de la interfaz, no la necesidad. Decir
-- que «la gama está resuelta» era falso; queda dicho.
--
-- **Por qué un flujo aparte y no columnas en la revisión de interpretación.**
-- Ésa fue la decisión del dueño y la comparto por una razón demostrada en este
-- mismo repositorio: `update_supply_need_v1` escribe su revisión manual con
-- `constraints '[]'` y **sin** `category_id` (20260816150000). Un writer que
-- ignora campos ya existe. Colgar columnas anulables de esa tabla obligaría a
-- cada writer —v2, v3, la confirmación de familia, el update genérico— a
-- copiarlas hacia adelante, y el primero que no lo haga **borra la preferencia
-- en silencio**. Un flujo append-only con un solo escritor no tiene esa
-- superficie: nadie más puede omitirlo porque nadie más escribe en él.
--
-- **La moneda es del servidor, siempre.** Sale de `tenants.currency` al
-- momento de fijar el target. Ni el modelo ni el cliente pueden enviarla: una
-- carga que traiga `currencyCode` se rechaza, porque el campo no es
-- representable en la entrada. No hay tipo de cambio en este sistema, así que
-- guardar la moneda del taller es lo único honesto; comparar un tope en pesos
-- contra un costo en dólares es lo que la evaluación futura tendrá que declarar
-- `unknown`, no algo que este corte pueda resolver.
--
-- **Los targets son preferencias blandas.** Ninguno elimina un candidato: eso
-- se reserva para la contradicción técnica demostrada. Este corte sólo los
-- guarda y los lee; nada rankea todavía.
--
-- **La moneda se denomina por revisión, no por lectura.** Un tope se fijó en
-- una moneda concreta; releerlo en la de hoy lo reinterpretaría. La lectura
-- devuelve la moneda de su revisión e informa aparte la del taller. Si el
-- taller cambió de moneda y hay un tope guardado, un parche que no lo reemplace
-- ni lo limpie **falla**; y reingresarlo explícitamente **re-denomina aunque el
-- número coincida**, porque el acto explícito es lo que cambia el significado.
-- Nadie convierte números: no hay tipo de cambio.
--
-- **Un no-op consume su clave.** No escribe revisión ni mueve la versión, pero
-- sí deja recibo con `changed = false`: sin eso, esa clave quedaría libre para
-- otra petición y el replay dejaría de significar algo. Las dos ramas devuelven
-- la misma forma.
--
-- Forward-only. `create_supply_need_batch_v2`, `*_v1` y
-- `rank_purchase_candidates_v1` quedan intactas.

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. El flujo append-only.
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.supply_need_commercial_revisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  supply_need_id uuid not null,
  revision_no bigint not null check (revision_no > 0),
  source text not null check (source in ('ai', 'manual', 'system')),

  -- Preferencias. Todas opcionales: una necesidad puede no tener ninguna.
  gama text check (gama in ('economica', 'media', 'alta')),
  preferred_brand_id uuid references public.product_brands(id)
    on delete restrict,
  -- Rangos explícitos. El `between` además rechaza `NaN` e `Infinity`, que
  -- `numeric` acepta como valores válidos: los dos son mayores que cero y
  -- ninguno cabe bajo el techo.
  max_landed_unit_cost_net numeric(18,4) check (
    max_landed_unit_cost_net > 0
    and max_landed_unit_cost_net <= 999999999
  ),
  min_gross_margin_ratio numeric(6,5) check (
    min_gross_margin_ratio >= 0 and min_gross_margin_ratio <= 1
  ),

  -- Moneda del taller al momento de fijar el target. Server-owned.
  currency_code text not null check (
    currency_code ~ '^[A-Z]{3}$'
  ),

  -- Una revisión de limpieza total: todos los campos en nulo, dicho
  -- explícitamente para que no se confunda con «nunca hubo target».
  cleared boolean not null default false,

  operation_key text not null check (
    btrim(operation_key) <> '' and octet_length(operation_key) <= 200
  ),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),

  unique (tenant_id, supply_need_id, revision_no),
  unique (tenant_id, operation_key),
  foreign key (tenant_id, supply_need_id)
    references public.supply_needs(tenant_id, id) on delete restrict,
  -- Una revisión dice algo: o fija al menos una preferencia, o declara que se
  -- limpió todo. Una fila con todo en nulo y `cleared=false` sería ruido.
  check (
    cleared is true
    or gama is not null
    or preferred_brand_id is not null
    or max_landed_unit_cost_net is not null
    or min_gross_margin_ratio is not null
  ),
  check (
    cleared is false
    or (gama is null and preferred_brand_id is null
      and max_landed_unit_cost_net is null
      and min_gross_margin_ratio is null)
  )
);

create index if not exists idx_supply_need_commercial_revisions_need
  on public.supply_need_commercial_revisions (
    tenant_id, supply_need_id, revision_no desc
  );

alter table public.supply_need_commercial_revisions enable row level security;
revoke all on public.supply_need_commercial_revisions
  from public, anon, authenticated, service_role;
grant select on public.supply_need_commercial_revisions to authenticated;

drop policy if exists "supply_need_commercial_revisions_select"
  on public.supply_need_commercial_revisions;
create policy "supply_need_commercial_revisions_select"
  on public.supply_need_commercial_revisions for select to authenticated
  using (tenant_id = public.user_tenant_id());

-- Append-only con el mismo guardián que el resto de la evidencia del kernel.
drop trigger if exists trg_supply_need_commercial_revisions_immutable
  on public.supply_need_commercial_revisions;
create trigger trg_supply_need_commercial_revisions_immutable
  before update or delete on public.supply_need_commercial_revisions
  for each row execute function public.prevent_supply_kernel_evidence_mutation();

comment on table public.supply_need_commercial_revisions is
  'Append-only stream of typed commercial preferences for a supply need. Separate from interpretation revisions on purpose: a nullable column there would be silently dropped by any writer that forgets to copy it forward, and update_supply_need_v1 already writes empty constraints and no category. currency_code is server-owned from tenants.currency.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. El ledger aprende dos hechos más.
-- ───────────────────────────────────────────────────────────────────────────
alter table public.supply_need_events
  drop constraint if exists supply_need_events_action_check;
alter table public.supply_need_events
  add constraint supply_need_events_action_check check (action in (
    'created', 'updated', 'cancelled',
    'stock_assigned', 'stock_released', 'stock_reactivated',
    'internal_stock_rejected',
    'family_stock_rejected',
    'family_choice_confirmed',
    'commercial_target_set',
    'commercial_target_cleared',
    'purchase_planned', 'received', 'covered'
  ));

-- ───────────────────────────────────────────────────────────────────────────
-- 3. La moneda del taller, con un solo dueño.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.tenant_commercial_currency_internal_v1(
  p_tenant_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_currency text;
begin
  select upper(btrim(coalesce(tenant.currency, ''))) into v_currency
  from public.tenants tenant
  where tenant.id = p_tenant_id;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'El taller no tiene una moneda válida configurada.'
      using errcode = '23514';
  end if;
  return v_currency;
end;
$$;

revoke all on function public.tenant_commercial_currency_internal_v1(uuid)
from public, anon, authenticated, service_role;

comment on function public.tenant_commercial_currency_internal_v1(uuid) is
  'Single owner of the currency a commercial target is denominated in. Derived from tenants.currency; never accepted from a client or a model.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Normalizar una carga de target.
--
-- **Semántica de la carga, sin ambigüedad.** Es un *parche*, no un reemplazo:
--   · clave ausente        → el campo se conserva como estaba;
--   · clave presente = null→ ese campo se limpia;
--   · `p_target` SQL null  → limpieza TOTAL (revisión con `cleared`).
--
-- La distinción entre «ausente» y «null» es la que hace posible limpiar un
-- campo sin tocar los otros, y jsonb la representa sin trucos.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.normalize_commercial_target_internal_v1(
  p_tenant_id uuid,
  p_current jsonb,
  p_patch jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_allowed constant text[] := array[
    'gama', 'preferredBrandId', 'maxLandedUnitCostNet', 'minGrossMarginRatio'
  ];
  v_result jsonb := coalesce(p_current, '{}'::jsonb);
  v_key text;
  v_gama text;
  v_brand_id uuid;
  v_cost numeric;
  v_margin numeric;
begin
  if jsonb_typeof(p_patch) <> 'object' then
    raise exception 'El objetivo comercial no es válido.' using errcode = '22023';
  end if;

  -- La moneda no es representable en la entrada: intentar enviarla es un
  -- error, no algo que el servidor deba ignorar en silencio.
  if p_patch ? 'currencyCode' then
    raise exception 'La moneda del objetivo comercial la fija el servidor.'
      using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Campo desconocido en el objetivo comercial: %', v_key
        using errcode = '22023';
    end if;
  end loop;

  if p_patch ? 'gama' then
    if jsonb_typeof(p_patch -> 'gama') = 'null' then
      v_result := v_result - 'gama';
    else
      v_gama := p_patch ->> 'gama';
      if v_gama not in ('economica', 'media', 'alta') then
        raise exception 'La gama del objetivo comercial no es válida.'
          using errcode = '22023';
      end if;
      v_result := v_result || jsonb_build_object('gama', v_gama);
    end if;
  end if;

  if p_patch ? 'preferredBrandId' then
    if jsonb_typeof(p_patch -> 'preferredBrandId') = 'null' then
      v_result := v_result - 'preferredBrandId';
    else
      if (p_patch ->> 'preferredBrandId') !~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then
        raise exception 'La marca preferida no es una identidad válida.'
          using errcode = '22023';
      end if;
      v_brand_id := (p_patch ->> 'preferredBrandId')::uuid;
      -- Visible para este taller: global (`tenant_id` nulo) o suya, y activa.
      -- Una marca de otro tenant o retirada no se acepta ni se ignora: se
      -- rechaza, porque el operador cree haber elegido algo.
      if not exists (
        select 1 from public.product_brands brand
        where brand.id = v_brand_id
          and brand.is_active is true
          and (brand.tenant_id is null or brand.tenant_id = p_tenant_id)
      ) then
        raise exception 'La marca preferida no está disponible para este taller.'
          using errcode = '23514';
      end if;
      v_result := v_result
        || jsonb_build_object('preferredBrandId', v_brand_id);
    end if;
  end if;

  if p_patch ? 'maxLandedUnitCostNet' then
    if jsonb_typeof(p_patch -> 'maxLandedUnitCostNet') = 'null' then
      v_result := v_result - 'maxLandedUnitCostNet';
    else
      if jsonb_typeof(p_patch -> 'maxLandedUnitCostNet') <> 'number' then
        raise exception 'El tope de costo aterrizado debe ser un número.'
          using errcode = '22023';
      end if;
      v_cost := (p_patch ->> 'maxLandedUnitCostNet')::numeric;
      -- `NaN` e `Infinity` son numeric válidos en Postgres y los dos son
      -- mayores que cero: el techo es lo que los deja fuera.
      if not (v_cost > 0 and v_cost <= 999999999) then
        raise exception 'El tope de costo aterrizado está fuera de rango.'
          using errcode = '22023';
      end if;
      v_result := v_result
        || jsonb_build_object('maxLandedUnitCostNet', round(v_cost, 4));
    end if;
  end if;

  if p_patch ? 'minGrossMarginRatio' then
    if jsonb_typeof(p_patch -> 'minGrossMarginRatio') = 'null' then
      v_result := v_result - 'minGrossMarginRatio';
    else
      if jsonb_typeof(p_patch -> 'minGrossMarginRatio') <> 'number' then
        raise exception 'El margen mínimo debe ser un número.'
          using errcode = '22023';
      end if;
      v_margin := (p_patch ->> 'minGrossMarginRatio')::numeric;
      if not (v_margin >= 0 and v_margin <= 1) then
        raise exception 'El margen mínimo está fuera de rango.'
          using errcode = '22023';
      end if;
      v_result := v_result
        || jsonb_build_object('minGrossMarginRatio', round(v_margin, 5));
    end if;
  end if;

  return v_result;
end;
$$;

revoke all on function public.normalize_commercial_target_internal_v1(
  uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;

comment on function public.normalize_commercial_target_internal_v1(
  uuid, jsonb, jsonb
) is
  'Validates and applies a commercial target patch: absent key preserves, explicit null clears that field. Rejects unknown keys, an unrepresentable currencyCode, out-of-range numbers including NaN and Infinity, and a brand that is not active and visible to the tenant.';

-- ───────────────────────────────────────────────────────────────────────────
-- 5. El target vigente.
--
-- Autocontenida: trae la versión y el estado de la necesidad que el comando
-- exige, la moneda **de la revisión que gobierna** y, aparte, la del taller.
-- `targetRevisionNo = 0` cuando nunca se fijó uno: la ausencia se dice.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_commercial_target_internal_v1(
  p_tenant_id uuid,
  p_need_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_need public.supply_needs%rowtype;
  v_revision public.supply_need_commercial_revisions%rowtype;
  v_legacy text;
  v_target jsonb := '{}'::jsonb;
  v_currency text;
  v_brand_available boolean;
begin
  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = p_tenant_id and need.id = p_need_id;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;

  select revision.* into v_revision
  from public.supply_need_commercial_revisions revision
  where revision.tenant_id = p_tenant_id
    and revision.supply_need_id = p_need_id
  order by revision.revision_no desc
  limit 1;

  -- La moneda del objetivo es la de su revisión. Sólo cuando no existe
  -- revisión se usa la del taller, porque ahí no hay historia que respetar.
  if found then
    v_currency := v_revision.currency_code;
  else
    v_currency := public.tenant_commercial_currency_internal_v1(p_tenant_id);
  end if;

  if v_revision.revision_no is not null and not v_revision.cleared then
    v_target := jsonb_strip_nulls(jsonb_build_object(
      'gama', v_revision.gama,
      'preferredBrandId', v_revision.preferred_brand_id,
      'maxLandedUnitCostNet', v_revision.max_landed_unit_cost_net,
      'minGrossMarginRatio', v_revision.min_gross_margin_ratio
    ));
  end if;

  -- Una marca elegida puede haberse retirado después. No se borra el objetivo
  -- —el operador la eligió— pero se dice, en vez de fingir que sigue servible.
  v_brand_available := case
    when v_revision.preferred_brand_id is null then null
    else exists (
      select 1 from public.product_brands brand
      where brand.id = v_revision.preferred_brand_id
        and brand.is_active is true
        and (brand.tenant_id is null or brand.tenant_id = p_tenant_id)
    )
  end;

  -- La nota legada sale de la revisión de interpretación **que gobierna**, no
  -- de la más antigua que la tuviera: si la última ya no la trae, no hay nota.
  select entry.value ->> 'value' into v_legacy
  from public.supply_need_interpretation_revisions revision
  cross join lateral jsonb_array_elements(revision.constraints) entry(value)
  where revision.tenant_id = p_tenant_id
    and revision.supply_need_id = p_need_id
    and revision.revision_no = (
      select max(latest.revision_no)
      from public.supply_need_interpretation_revisions latest
      where latest.tenant_id = p_tenant_id
        and latest.supply_need_id = p_need_id
    )
    and entry.value ->> 'kind' = 'commercial_preference'
  limit 1;

  return jsonb_build_object(
    'needId', p_need_id,
    'needVersion', v_need.version,
    'needSupplyState', v_need.supply_state,
    'currencyCode', v_currency,
    'tenantCurrencyCode',
      public.tenant_commercial_currency_internal_v1(p_tenant_id),
    'targetRevisionNo', coalesce(v_revision.revision_no, 0),
    'target', v_target,
    'preferredBrandAvailable', v_brand_available,
    'legacyPreferenceNote', case
      when v_legacy is null then null
      else jsonb_build_object('text', v_legacy, 'drivesRanking', false)
    end
  );
end;
$$;

revoke all on function public.supply_need_commercial_target_internal_v1(
  uuid, uuid
) from public, anon, authenticated, service_role;

create or replace function public.get_supply_need_commercial_target_v1(
  p_need_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  if v_tenant_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  return public.supply_need_commercial_target_internal_v1(
    v_tenant_id, p_need_id
  );
end;
$$;

revoke all on function public.get_supply_need_commercial_target_v1(uuid)
from public, anon, authenticated, service_role;
grant execute on function public.get_supply_need_commercial_target_v1(uuid)
to authenticated;

comment on function public.get_supply_need_commercial_target_v1(uuid) is
  'Current typed commercial target. currencyCode is the currency of the governing revision, never today''s tenant currency, so a shop that changes currency cannot silently reinterpret a stored ceiling; tenantCurrencyCode reports today''s for comparison. Self-contained: carries the need version and supply state the set command demands.';

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Fijar o limpiar el target.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.set_supply_need_commercial_target_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_expected_target_revision_no bigint,
  p_target jsonb,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_current jsonb;
  v_current_revision bigint;
  v_current_currency text;
  v_tenant_currency text;
  v_next jsonb;
  v_clear_all boolean := p_target is null;
  v_currency_rebase boolean := false;
  v_next_revision bigint;
  v_changed boolean;
  v_action text;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_expected_target_revision_no is null
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'El objetivo comercial requiere necesidad, versión, revisión y clave.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'expected_target_revision_no', p_expected_target_revision_no,
    'target', coalesce(p_target, 'null'::jsonb)
  );

  -- **El lock va antes de leer el recibo, no después.** Sin esto, dos
  -- peticiones idénticas simultáneas pasan las dos por el `select`, las dos
  -- creen ser la primera, y la segunda termina en `40001` —si la primera subió
  -- la versión— o en una violación de unicidad cruda si ambas eran no-op. Lo
  -- correcto es que la segunda vea `replay = true`. El ámbito incluye el
  -- tenant: dos talleres pueden usar la misma clave sin bloquearse.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':supply_need_commercial_target:' || v_operation_key, 0
  ));

  select event.* into v_receipt
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action not in (
         'commercial_target_set', 'commercial_target_cleared'
       )
       or v_receipt.supply_need_id <> p_need_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro objetivo comercial.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de fijar el objetivo.'
      using errcode = '40001';
  end if;
  -- Misma frontera que `update_supply_need_v1`.
  if v_need.supply_state in ('covered', 'cancelled') then
    raise exception 'La necesidad ya está cerrada; no admite objetivo comercial.'
      using errcode = '55000';
  end if;

  v_current := public.supply_need_commercial_target_internal_v1(
    v_tenant_id, p_need_id
  );
  v_current_revision := (v_current ->> 'targetRevisionNo')::bigint;
  if v_current_revision <> p_expected_target_revision_no then
    raise exception 'El objetivo comercial cambió; vuelve a cargarlo.'
      using errcode = '40001';
  end if;
  v_current_currency := v_current ->> 'currencyCode';
  v_tenant_currency := v_current ->> 'tenantCurrencyCode';

  if v_clear_all then
    v_next := '{}'::jsonb;
  else
    v_next := public.normalize_commercial_target_internal_v1(
      v_tenant_id, v_current -> 'target', p_target
    );

    -- **Rebase explícito de moneda, sin convertir nada.** Arrastrar un tope a
    -- una revisión en otra moneda lo reinterpretaría: 12.000 dejaría de ser
    -- 12.000 pesos y pasaría a ser 12.000 dólares sin que nadie lo decidiera.
    if v_current_currency is distinct from v_tenant_currency
       and (v_current -> 'target') ? 'maxLandedUnitCostNet'
       and not (p_target ? 'maxLandedUnitCostNet') then
      raise exception 'La moneda del taller cambió de % a %: reemplaza o limpia el tope de costo antes de editar el objetivo.',
        v_current_currency, v_tenant_currency
        using errcode = '23514';
    end if;

    -- **Re-denominar es un cambio aunque el número coincida.** Reingresar
    -- explícitamente 12.000 bajo otra moneda no deja el objetivo igual: deja
    -- de significar pesos y pasa a significar dólares. Comparar sólo los
    -- números lo daría por no-op y la lectura seguiría diciendo la moneda
    -- vieja, que es justo el silencio que este contrato evita.
    v_currency_rebase := v_current_currency is distinct from v_tenant_currency
      and (p_target ? 'maxLandedUnitCostNet')
      and (v_next ? 'maxLandedUnitCostNet');
  end if;

  v_changed := (v_next is distinct from (v_current -> 'target'))
    or v_currency_rebase;
  v_action := case when v_next = '{}'::jsonb
    then 'commercial_target_cleared' else 'commercial_target_set' end;

  if v_changed then
    select coalesce(max(revision.revision_no), 0) + 1 into v_next_revision
    from public.supply_need_commercial_revisions revision
    where revision.tenant_id = v_tenant_id
      and revision.supply_need_id = p_need_id;

    insert into public.supply_need_commercial_revisions (
      tenant_id, supply_need_id, revision_no, source, gama, preferred_brand_id,
      max_landed_unit_cost_net, min_gross_margin_ratio, currency_code, cleared,
      operation_key, created_by
    ) values (
      v_tenant_id, p_need_id, v_next_revision, 'manual',
      v_next ->> 'gama',
      nullif(v_next ->> 'preferredBrandId', '')::uuid,
      (v_next ->> 'maxLandedUnitCostNet')::numeric,
      (v_next ->> 'minGrossMarginRatio')::numeric,
      v_tenant_currency,
      v_next = '{}'::jsonb,
      v_operation_key, v_actor_id
    );

    update public.supply_needs need
    set version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;
  else
    v_next_revision := v_current_revision;
  end if;

  v_response := jsonb_build_object(
    'need_id', p_need_id,
    'changed', v_changed,
    'currency_rebase', v_currency_rebase,
    'target_revision_no', v_next_revision,
    'version', v_need.version,
    'currency_code', case when v_changed then v_tenant_currency
      else v_current_currency end,
    'target', v_next
  );
  -- Un no-op también deja recibo: la clave se consume igual.
  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, p_need_id, v_action, v_changed, v_actor_id, v_operation_key,
    v_request, v_response, clock_timestamp()
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.set_supply_need_commercial_target_v1(
  uuid, bigint, bigint, jsonb, text
) from public, anon, authenticated, service_role;
grant execute on function public.set_supply_need_commercial_target_v1(
  uuid, bigint, bigint, jsonb, text
) to authenticated;

comment on function public.set_supply_need_commercial_target_v1(
  uuid, bigint, bigint, jsonb, text
) is
  'Replay-safe set/clear of the typed commercial target. A no-op writes no revision and does not bump the version, but still consumes its operation key; both paths return the same shape. If the shop currency changed while a ceiling exists, an edit that does not explicitly replace or clear it fails, and explicitly re-entering it re-denominates even when the number is identical. Numbers are never converted.';

-- ───────────────────────────────────────────────────────────────────────────
-- 7. `create_supply_need_batch_v3`.
--
-- Recibo propio en el **mismo espacio de nombres** que v2, con el request
-- **normalizado**: los ítems tal como v2 los deja —sin las glosas derivadas—
-- más sólo los objetivos accionables, indexados por el `lineRef` real. Así dos
-- llamadas que difieren únicamente en espacios, en la forma de un número o en
-- un `commercialTarget` vacío son el mismo replay, y una diferencia real sigue
-- siendo colisión.
--
-- Las claves internas son de tamaño fijo y se derivan de una **semilla
-- generada dentro de la transacción**, no de la clave pública: una fórmula
-- determinista sería presembrable por cualquiera del mismo taller. El límite
-- público de 160 bytes se conserva tal cual.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.create_supply_need_batch_v3(
  p_original_request text,
  p_items jsonb,
  p_profile text,
  p_assistant_thread_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_seed uuid;
  v_delegate_key text;
  v_targets jsonb := '{}'::jsonb;
  v_items_v2 jsonb := '[]'::jsonb;
  v_normalized_items jsonb;
  v_item jsonb;
  v_line_ref text;
  v_target jsonb;
  v_normalized jsonb;
  v_currency text;
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_batch_receipts%rowtype;
  v_need jsonb;
  v_matched integer := 0;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  -- El límite público es el histórico de v2: 160 bytes.
  if v_operation_key = '' or octet_length(v_operation_key) > 160 then
    raise exception 'La petición de abastecimiento no es válida.'
      using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'La petición de abastecimiento no es válida.'
      using errcode = '22023';
  end if;

  v_currency := public.tenant_commercial_currency_internal_v1(v_tenant_id);

  -- Los objetivos se validan y se indexan por el `lineRef` **real**: v2 acepta
  -- `line-1..line-8` en cualquier orden, y usar la posición del arreglo
  -- asignaría el objetivo a otra línea.
  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'La petición de abastecimiento no es válida.'
        using errcode = '22023';
    end if;
    v_line_ref := v_item ->> 'lineRef';
    if v_line_ref is null or v_line_ref !~ '^line-[1-8]$' then
      raise exception 'La línea de la petición no tiene una referencia válida.'
        using errcode = '22023';
    end if;
    if v_item ? 'commercialTarget'
       and jsonb_typeof(v_item -> 'commercialTarget') = 'object' then
      v_normalized := public.normalize_commercial_target_internal_v1(
        v_tenant_id, '{}'::jsonb, v_item -> 'commercialTarget'
      );
      -- Un objetivo vacío equivale a no traer ninguno.
      if v_normalized <> '{}'::jsonb then
        if v_targets ? v_line_ref then
          raise exception 'La referencia de línea % está repetida.', v_line_ref
            using errcode = '22023';
        end if;
        v_targets := v_targets || jsonb_build_object(v_line_ref, v_normalized);
      end if;
    elsif v_item ? 'commercialTarget'
       and jsonb_typeof(v_item -> 'commercialTarget') <> 'null' then
      raise exception 'El objetivo comercial no es válido.' using errcode = '22023';
    end if;
    v_items_v2 := v_items_v2 || jsonb_build_array(v_item - 'commercialTarget');
  end loop;

  -- El request del recibo es el **estable**: los ítems tal como v2 los
  -- normaliza, sin `categoryPath` ni `technicalFamily` —derivadas que envejecen
  -- junto a su fuente y romperían el replay tras un rename—, más los objetivos
  -- ya normalizados. Guardar el payload crudo haría que un espacio de más
  -- pareciera otra petición.
  select coalesce(jsonb_agg(
    (entry.value - 'categoryPath' - 'technicalFamily')
      || case
        when v_targets ? (entry.value ->> 'lineRef')
          then jsonb_build_object(
            'commercialTarget', v_targets -> (entry.value ->> 'lineRef'))
        else '{}'::jsonb
      end
    order by entry.ordinality
  ), '[]'::jsonb)
  into v_normalized_items
  from jsonb_array_elements(
    public.normalize_supply_request_items_internal_v2(v_tenant_id, v_items_v2)
  ) with ordinality entry(value, ordinality);

  v_request := jsonb_build_object(
    'version', 3,
    'original_request', btrim(coalesce(p_original_request, '')),
    'items', v_normalized_items,
    'profile', p_profile,
    'assistant_thread_id', p_assistant_thread_id
  );

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':supply_need_batch:' || v_operation_key, 0
  ));

  select receipt.* into v_receipt
  from public.supply_need_batch_receipts receipt
  where receipt.tenant_id = v_tenant_id
    and receipt.operation_key = v_operation_key;
  if found then
    if v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otra petición.'
        using errcode = '23505';
    end if;
    return v_receipt.response_snapshot || jsonb_build_object('replay', true);
  end if;

  -- **La clave interna no se deriva de la pública.** Una fórmula determinista
  -- como `md5(tenant:clave)` es presembrable: cualquiera del mismo taller puede
  -- llamar antes a v2 con exactamente esa clave y una petición base; entonces
  -- v3 encontraría el recibo ajeno, replayaría **necesidades viejas** y les
  -- colgaría los objetivos nuevos. El semilla se genera acá dentro, después de
  -- tomar el lock externo y de comprobar que la clave pública está libre, así
  -- que nadie puede adivinarla. Se usa además como identidad del recibo
  -- externo, de modo que la traza queda auditable.
  v_seed := gen_random_uuid();
  v_delegate_key := 'v3-core:' || v_seed::text;

  v_response := public.create_supply_need_batch_v2(
    p_original_request, v_items_v2, p_profile, p_assistant_thread_id,
    v_delegate_key
  );

  for v_need in select value from jsonb_array_elements(v_response -> 'needs')
  loop
    v_target := v_targets -> (v_need ->> 'line_ref');
    if v_target is null then continue; end if;
    v_matched := v_matched + 1;
    -- Sin `on conflict do nothing`: la clave externa se reservó una sola vez.
    insert into public.supply_need_commercial_revisions (
      tenant_id, supply_need_id, revision_no, source, gama, preferred_brand_id,
      max_landed_unit_cost_net, min_gross_margin_ratio, currency_code, cleared,
      operation_key, created_by
    ) values (
      v_tenant_id, (v_need ->> 'id')::uuid, 1, 'ai',
      v_target ->> 'gama',
      nullif(v_target ->> 'preferredBrandId', '')::uuid,
      (v_target ->> 'maxLandedUnitCostNet')::numeric,
      (v_target ->> 'minGrossMarginRatio')::numeric,
      v_currency, false,
      'v3-target:' || v_seed::text || ':' || (v_need ->> 'line_ref'),
      v_actor_id
    );
  end loop;

  if v_matched <> (select count(*)::integer from jsonb_object_keys(v_targets))
  then
    raise exception 'Un objetivo comercial no encontró su línea.'
      using errcode = '23514';
  end if;

  v_response := v_response || jsonb_build_object(
    'commercial_currency_code', v_currency,
    'commercial_target_line_count', v_matched
  );

  insert into public.supply_need_batch_receipts (
    id, tenant_id, actor_id, assistant_thread_id, operation_key,
    request_snapshot, response_snapshot
  ) values (
    -- La semilla es la identidad del recibo: las claves internas que creó se
    -- pueden rastrear hasta él sin adivinarlas desde la clave pública.
    v_seed, v_tenant_id, v_actor_id, p_assistant_thread_id, v_operation_key,
    v_request, v_response
  );

  return v_response || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.create_supply_need_batch_v3(
  text, jsonb, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_supply_need_batch_v3(
  text, jsonb, text, uuid, text
) to authenticated;

comment on function public.create_supply_need_batch_v3(
  text, jsonb, text, uuid, text
) is
  'Creates a reviewed supply-request batch together with its first typed commercial targets, atomically. Owns its receipt in the shared supply_need_batch_receipts namespace, keyed on the normalized request — v2-normalized items without derived glosses, plus only actionable targets indexed by the real lineRef — so cosmetic differences replay and real ones collide. Internal keys are fixed size, so the public 160-byte limit is preserved.';

commit;
