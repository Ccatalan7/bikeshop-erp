-- La ficha toma lo instalado al terminar el trabajo (paso C del backbone,
-- 2026-09-27).
--
-- Configurar un servicio no cambia la bici: el Enrayado pregunta las
-- perforaciones de la rueda que se va a armar, y un presupuesto rechazado no
-- debe dejar la ficha en 28H si la bici sigue con su rueda de 32H. Con
-- `p_source = 'job_completion'` el comando escribe ese estado instalado sólo
-- con el trabajo en FINALIZADO o ENTREGADO (el mismo corte de la memoria de la
-- bici), sólo con `set`, y deja la fuente `job_completion` en la ficha, el
-- recibo y la historia.
--
-- Reemplaza el cuerpo de patch_bike_technical_facts_v1 (misma firma y mismos
-- permisos que 20260927040000).

begin;

alter table public.bike_technical_fact_patches
  drop constraint if exists bike_technical_fact_patches_source_check;
alter table public.bike_technical_fact_patches
  add constraint bike_technical_fact_patches_source_check
  check (source in ('service_wizard', 'job_completion'));

create or replace function public.patch_bike_technical_facts_v1(
  p_operation_key text,
  p_bike_id uuid,
  p_job_id uuid,
  p_source text,
  p_facts jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_active_profile_count integer;
  v_operation_key text := nullif(btrim(p_operation_key), '');
  v_operation_id uuid := gen_random_uuid();
  v_payload_hash text;
  v_operation public.bike_technical_fact_patches%rowtype;
  v_bike public.bikes%rowtype;
  v_profile public.bike_profiles%rowtype;
  v_profile_exists boolean := false;
  v_values jsonb;
  v_sources jsonb;
  v_confirmed jsonb;
  v_fact jsonb;
  v_key text;
  v_op text;
  v_kind text;
  v_value jsonb;
  v_expected jsonb;
  v_expected_confirmed boolean;
  v_current jsonb;
  v_number numeric;
  v_text text;
  v_seen text[] := array[]::text[];
  v_conflicts jsonb := '[]'::jsonb;
  v_applied jsonb := '[]'::jsonb;
  v_technical_changed boolean := false;
  v_confirmed_any boolean;
  -- Quién afirma el dato en la ficha: el mecánico al configurar, o el trabajo
  -- terminado que dejó la pieza instalada.
  v_fact_source text := case p_source
    when 'job_completion' then 'job_completion'
    else 'mechanic'
  end;
  v_wheel_size text;
  v_wheel_changed boolean := false;
  v_result jsonb;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select tenant_id
    into v_tenant_id
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  -- Un taller suspendido no escribe fichas aunque la cuenta siga activa: el
  -- comando es definer y se salta las políticas que sí lo exigen.
  if not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  if v_operation_key is null or length(v_operation_key) > 128 then
    raise exception 'A valid bicycle fact operation key is required';
  end if;

  if p_bike_id is null then
    raise exception 'Bicycle id is required';
  end if;

  if p_source is null or p_source not in ('service_wizard', 'job_completion') then
    raise exception 'Unsupported bicycle fact source';
  end if;

  -- Un servicio siempre pertenece a un trabajo: sin él no hay recibo ni
  -- historia que expliquen el cambio.
  if p_job_id is null then
    raise exception 'A service fact needs the job that confirmed it';
  end if;

  if p_facts is null
     or jsonb_typeof(p_facts) <> 'array'
     or jsonb_array_length(p_facts) = 0
     or jsonb_array_length(p_facts) > 32 then
    raise exception 'Bicycle facts must be a non-empty array of at most 32 items';
  end if;

  -- Forma de cada dato, antes de tocar nada.
  for v_fact in select value from jsonb_array_elements(p_facts)
  loop
    if jsonb_typeof(v_fact) <> 'object'
       or not (
         v_fact ? 'key' and v_fact ? 'op' and v_fact ? 'expected'
         and v_fact ? 'expected_confirmed'
       )
       or jsonb_typeof(v_fact->'expected_confirmed') <> 'boolean'
       or exists (
         select 1 from jsonb_object_keys(v_fact) as fact_key
          where fact_key <> all (array[
            'key', 'op', 'value', 'expected', 'expected_confirmed'
          ]::text[])
       ) then
      raise exception 'Each bicycle fact needs key, op, expected and expected_confirmed, and nothing else';
    end if;

    v_key := v_fact->>'key';
    v_op := v_fact->>'op';
    v_value := v_fact->'value';
    v_kind := case
      when v_key in (
        'frontRotorSizeMm', 'rearRotorSizeMm', 'drivetrainSpeeds',
        'bbShellWidthMm', 'bbShellDiameterMm', 'frontSpokeHoles',
        'rearSpokeHoles'
      ) then 'number'
      when v_key in (
        'brakeType', 'rimBrakeFamily', 'drivetrainConfig', 'freehubType',
        'bottomBracketFamily', 'spindleInterface', 'valveType'
      ) then 'string'
      when v_key = 'bikes.wheel_size' then 'wheel_size'
    end;

    if v_kind is null then
      raise exception 'Bicycle fact key % is not writable from a service', v_key;
    end if;

    if v_key = any (v_seen) then
      raise exception 'Bicycle fact key % appears twice', v_key;
    end if;
    v_seen := v_seen || v_key;

    -- Lo instalado cambia la ficha; no sugiere ni borra.
    if p_source = 'job_completion' and v_op <> 'set' then
      raise exception 'A finished job only sets installed bicycle facts';
    end if;

    if v_op in ('set', 'suggest') then
      if v_op = 'suggest' and v_kind = 'wheel_size' then
        raise exception 'Bicycle wheel size has no confirmation mark to hold a suggestion';
      end if;
      if v_value is null or v_value = 'null'::jsonb then
        raise exception 'Bicycle fact % needs a value; use op remove to clear it', v_key;
      end if;
      if v_kind = 'number' then
        if jsonb_typeof(v_value) <> 'number' then
          raise exception 'Bicycle fact % must be a number', v_key;
        end if;
        v_number := (v_value #>> '{}')::numeric;
        -- Rangos de taller: fuera de ellos es un error de tipeo, no una bici.
        if not (case v_key
          when 'frontSpokeHoles' then v_number = trunc(v_number) and v_number between 12 and 48
          when 'rearSpokeHoles' then v_number = trunc(v_number) and v_number between 12 and 48
          when 'drivetrainSpeeds' then v_number = trunc(v_number) and v_number between 1 and 14
          when 'frontRotorSizeMm' then v_number = trunc(v_number) and v_number between 100 and 260
          when 'rearRotorSizeMm' then v_number = trunc(v_number) and v_number between 100 and 260
          when 'bbShellWidthMm' then v_number between 60 and 130
          when 'bbShellDiameterMm' then v_number between 30 and 60
          else false
        end) then
          raise exception 'Bicycle fact % is out of its workshop range', v_key;
        end if;
      end if;
      if v_kind = 'string' then
        if jsonb_typeof(v_value) <> 'string' then
          raise exception 'Bicycle fact % must be text', v_key;
        end if;
        v_text := v_value #>> '{}';
        -- «Desconocido» no es un dato de la bici: la ficha lo guarda como
        -- revisado sin confirmar, y un servicio sólo escribe lo que confirma.
        if lower(v_text) in ('unknown', 'desconocido') then
          raise exception 'Bicycle fact % cannot be confirmed as unknown', v_key;
        end if;
        -- Vocabularios cerrados de brake_canonical_data.dart y de la ficha;
        -- las claves que vienen del registro de especificaciones se validan
        -- por forma hasta que el registro sea la única fuente.
        if not (case v_key
          when 'brakeType' then v_text in (
            'rim', 'mechanical_disc', 'hydraulic_disc', 'roller_brake',
            'drum_brake', 'coaster_brake', 'band_brake')
          when 'rimBrakeFamily' then v_text in (
            'v_brake', 'cantilever', 'road_caliper_short_reach',
            'road_caliper_long_reach', 'u_brake', 'rod_brake', 'other')
          when 'valveType' then v_text in ('presta', 'schrader', 'dunlop', 'other')
          when 'drivetrainConfig' then v_text ~ '^([1-3]x([1-9]|1[0-4])|singlespeed)$'
          else v_text ~ '^[a-z0-9_]{2,40}$'
        end) then
          raise exception 'Bicycle fact % has an unknown value', v_key;
        end if;
      end if;
      if v_kind = 'wheel_size' and (
        jsonb_typeof(v_value) <> 'string'
        or (v_value #>> '{}') <> all (array[
          '12"', '16"', '20"', '24"', '26"', '27.5"', '29"', '700c', '650b'
        ]::text[])
      ) then
        raise exception 'Bicycle wheel size must be one of the ficha labels';
      end if;
    elsif v_op = 'remove' then
      if v_fact ? 'value' and v_fact->'value' <> 'null'::jsonb then
        raise exception 'Removing bicycle fact % does not take a value', v_key;
      end if;
    else
      raise exception 'Bicycle fact op must be set, suggest or remove';
    end if;
  end loop;

  v_payload_hash := encode(extensions.digest(jsonb_build_object(
    'bike_id', p_bike_id,
    'job_id', p_job_id,
    'source', p_source,
    'facts', p_facts
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant_id::text || ':bike_fact_patch:' || v_operation_key, 0)
  );

  select *
    into v_operation
    from public.bike_technical_fact_patches
   where tenant_id = v_tenant_id
     and operation_key = v_operation_key;

  if found then
    if v_operation.payload_hash is distinct from v_payload_hash then
      raise exception 'Bicycle fact key was already used with different content'
        using errcode = 'integrity_constraint_violation';
    end if;

    return v_operation.result_snapshot || jsonb_build_object('replayed', true);
  end if;

  select *
    into v_bike
    from public.bikes
   where id = p_bike_id
     and tenant_id = v_tenant_id
   for update;

  if not found then
    raise exception 'Bicycle not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1
      from public.mechanic_jobs j
     where j.id = p_job_id
       and j.tenant_id = v_tenant_id
       and (
         j.bike_id = v_bike.id
         or exists (
           select 1
             from public.mechanic_job_bikes jb
            where jb.job_id = j.id
              and jb.tenant_id = v_tenant_id
              and jb.bike_id = v_bike.id
         )
       )
  ) then
    raise exception 'The job does not include this bicycle'
      using errcode = 'insufficient_privilege';
  end if;

  -- Una pieza cambia la bici cuando se instaló, no cuando se configuró o se
  -- presupuestó: `job_completion` exige el trabajo terminado, el mismo corte
  -- que usa la memoria de la bici para registrar piezas.
  if p_source = 'job_completion' and not exists (
    select 1
      from public.mechanic_jobs j
     where j.id = p_job_id
       and j.tenant_id = v_tenant_id
       and j.status in ('FINALIZADO', 'ENTREGADO')
  ) then
    raise exception 'Installed parts change the bicycle only when the job is finished';
  end if;

  select *
    into v_profile
    from public.bike_profiles
   where bike_id = v_bike.id
     and tenant_id = v_tenant_id
   for update;
  v_profile_exists := found;

  v_values := coalesce(v_profile.technical_profile->'values', '{}'::jsonb);
  v_sources := coalesce(v_profile.technical_profile->'sources', '{}'::jsonb);
  v_confirmed := coalesce(v_profile.technical_profile->'confirmed', '{}'::jsonb);
  v_wheel_size := v_bike.wheel_size;

  for v_fact in select value from jsonb_array_elements(p_facts)
  loop
    v_key := v_fact->>'key';
    v_op := v_fact->>'op';
    v_value := v_fact->'value';
    v_expected := coalesce(v_fact->'expected', 'null'::jsonb);
    v_expected_confirmed := (v_fact->>'expected_confirmed')::boolean;

    if v_key = 'bikes.wheel_size' then
      v_current := coalesce(to_jsonb(v_bike.wheel_size), 'null'::jsonb);
    else
      v_current := coalesce(v_values->v_key, 'null'::jsonb);
    end if;

    -- Una sugerencia (un dato de la bici completa visto en una sola rueda)
    -- sólo llena lo que la ficha no sabe, vacío o «desconocido», y lo deja sin
    -- confirmar. Nunca pisa un dato, así que no compara lo esperado ni choca
    -- con un cambio ajeno: si otro ya lo escribió, la sugerencia sobra.
    if v_op = 'suggest' then
      if v_current = 'null'::jsonb
         or lower(v_current #>> '{}') in ('unknown', 'desconocido') then
        v_values := v_values || jsonb_build_object(v_key, v_value);
        v_sources := v_sources || jsonb_build_object(v_key, 'service_wizard');
        v_confirmed := v_confirmed - v_key;
        v_technical_changed := true;
        v_applied := v_applied || jsonb_build_array(jsonb_build_object(
          'key', v_key, 'op', 'suggest', 'from', v_current, 'to', v_value
        ));
      end if;
      continue;
    end if;

    -- Primero la precondición, también cuando ya dice lo que se quiere
    -- escribir: una copia vieja que afirma el valor que otro dejó sin
    -- confirmar lo confirmaría sin haberlo visto (Codex, 2026-09-27). El mismo
    -- valor confirmado por otro también es un cambio ajeno.
    if v_current <> v_expected
       or (
         v_key <> 'bikes.wheel_size'
         and coalesce(v_confirmed->>v_key, 'false') <> v_expected_confirmed::text
       ) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'key', v_key, 'expected', v_expected, 'current', v_current
      ));
      continue;
    end if;

    -- Ya dice lo mismo. Una clave técnica sin confirmar queda confirmada,
    -- porque el mecánico la acaba de afirmar.
    if v_op = 'set' and v_current = v_value then
      if v_key <> 'bikes.wheel_size'
         and coalesce(v_confirmed->>v_key, 'false') <> 'true' then
        v_sources := v_sources || jsonb_build_object(v_key, v_fact_source);
        v_confirmed := v_confirmed || jsonb_build_object(v_key, true);
        v_technical_changed := true;
        v_applied := v_applied || jsonb_build_array(jsonb_build_object(
          'key', v_key, 'op', 'confirm', 'from', v_current, 'to', v_value
        ));
      end if;
      continue;
    end if;

    if v_op = 'remove' and v_current = 'null'::jsonb then
      continue;
    end if;

    if v_key = 'bikes.wheel_size' then
      v_wheel_size := case when v_op = 'set' then v_value #>> '{}' end;
      v_wheel_changed := true;
    elsif v_op = 'set' then
      v_values := v_values || jsonb_build_object(v_key, v_value);
      v_sources := v_sources || jsonb_build_object(v_key, v_fact_source);
      v_confirmed := v_confirmed || jsonb_build_object(v_key, true);
      v_technical_changed := true;
    else
      v_values := v_values - v_key;
      v_sources := v_sources - v_key;
      v_confirmed := v_confirmed - v_key;
      v_technical_changed := true;
    end if;

    v_applied := v_applied || jsonb_build_array(jsonb_build_object(
      'key', v_key,
      'op', v_op,
      'from', v_current,
      'to', case when v_op = 'set' then v_value else 'null'::jsonb end
    ));
  end loop;

  if jsonb_array_length(v_conflicts) > 0 then
    raise exception 'Bicycle facts changed since they were loaded; reload before saving'
      using errcode = 'serialization_failure',
            detail = v_conflicts::text;
  end if;

  -- «Última confirmación» es la de un mecánico: una sugerencia sola, vista en
  -- una rueda, no la renueva.
  v_confirmed_any := jsonb_path_exists(v_applied, '$[*] ? (@.op != "suggest")');

  if v_wheel_changed then
    update public.bikes
       set wheel_size = v_wheel_size
     where id = v_bike.id
       and tenant_id = v_tenant_id
     returning * into v_bike;
  end if;

  if v_technical_changed then
    if v_profile_exists then
      update public.bike_profiles
         set technical_profile = coalesce(technical_profile, '{}'::jsonb)
               || jsonb_build_object(
                    'values', v_values,
                    'sources', v_sources,
                    'confirmed', v_confirmed
                  ),
             summary_snapshot = '{}'::jsonb,
             last_confirmed_at = case
               when v_confirmed_any then clock_timestamp()
               else last_confirmed_at
             end
       where id = v_profile.id
         and tenant_id = v_tenant_id
       returning * into v_profile;
    else
      insert into public.bike_profiles (
        tenant_id, bike_id, intake_profile, technical_profile,
        summary_snapshot, last_confirmed_at
      ) values (
        v_tenant_id,
        v_bike.id,
        '{}'::jsonb,
        jsonb_build_object(
          'values', v_values,
          'sources', v_sources,
          'confirmed', v_confirmed
        ),
        '{}'::jsonb,
        case when v_confirmed_any then clock_timestamp() end
      )
      returning * into v_profile;
    end if;
  elsif v_wheel_changed and v_profile_exists then
    -- El aro también sale en el resumen: se vacía para que se reconstruya.
    update public.bike_profiles
       set summary_snapshot = '{}'::jsonb
     where id = v_profile.id
       and tenant_id = v_tenant_id
     returning * into v_profile;
  end if;

  if jsonb_array_length(v_applied) > 0 then
    insert into public.bike_events (
      tenant_id, bike_id, job_id, event_type, event_category, event_date,
      title, summary, source, payload, created_by
    ) values (
      v_tenant_id,
      v_bike.id,
      p_job_id,
      case
        when v_technical_changed and not v_profile_exists then 'profile_created'
        else 'profile_updated'
      end,
      'state',
      clock_timestamp(),
      case
        when p_source = 'job_completion'
          then 'Ficha actualizada al terminar el trabajo'
        when v_technical_changed and not v_profile_exists
          then 'Ficha creada desde un servicio'
        else 'Ficha actualizada desde un servicio'
      end,
      case
        when p_source = 'job_completion'
          then 'El trabajo terminado dejó instaladas piezas que cambian la ficha de la bicicleta.'
        when v_technical_changed and not v_profile_exists
          then 'Un servicio del trabajo abrió la ficha de la bicicleta con los datos que confirmó.'
        when not jsonb_path_exists(v_applied, '$[*] ? (@.op != "suggest")')
          then 'Un servicio del trabajo sugirió datos de la ficha que vio en una sola rueda, sin confirmarlos.'
        else 'Un servicio del trabajo confirmó datos de la ficha de la bicicleta.'
      end,
      case p_source
        when 'job_completion' then 'job_completion'
        else 'service_wizard_promotion'
      end,
      jsonb_build_object(
        'operation_id', v_operation_id,
        'operation_key', v_operation_key,
        'facts', v_applied
      ),
      v_actor_id
    );
  end if;

  v_result := jsonb_build_object(
    'operation_id', v_operation_id,
    'bike', to_jsonb(v_bike),
    'profile', case when v_profile.id is null then null else to_jsonb(v_profile) end,
    'applied', v_applied,
    'replayed', false
  );

  insert into public.bike_technical_fact_patches (
    id, tenant_id, operation_key, payload_hash, bike_id, profile_id, job_id,
    source, applied, result_snapshot, created_by
  ) values (
    v_operation_id,
    v_tenant_id,
    v_operation_key,
    v_payload_hash,
    v_bike.id,
    v_profile.id,
    p_job_id,
    p_source,
    v_applied,
    v_result,
    v_actor_id
  );

  return v_result;
end;
$$;

revoke all on function public.patch_bike_technical_facts_v1(
  text, uuid, uuid, text, jsonb
) from public, anon, service_role;

grant execute on function public.patch_bike_technical_facts_v1(
  text, uuid, uuid, text, jsonb
) to authenticated;

commit;
