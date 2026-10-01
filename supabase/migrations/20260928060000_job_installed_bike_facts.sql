-- Deployment status: NOT DEPLOYED
-- Lo instalado cambia la ficha en la misma transacción que termina el trabajo
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, ítem 4).
--
-- Hasta aquí la app, después de `transition_mechanic_job_status`, leía las
-- líneas, calculaba lo que dejaron instalado (hoy, las perforaciones de la
-- rueda que armó el Enrayado), buscaba los recibos y llamaba a
-- `patch_bike_technical_facts_v1` con fuente `job_completion`. Si la app moría
-- entre la transición y ese parche, lo instalado esperaba a una próxima
-- sincronización del trabajo que podía no llegar, y la regla vivía dos veces:
-- en Dart para calcular y en SQL para validar.
--
-- Ahora la regla vive en el servidor, en un solo lugar:
--
-- * `apply_job_installed_bike_facts_internal` deriva lo instalado de las
--   líneas guardadas (la rueda de la línea: su ubicación, o `which_wheel` si
--   es `none`; y su `hole_count`) y lo escribe por la misma puerta,
--   `patch_bike_technical_facts_v1`, con la misma llave
--   `job_completion:<línea>:<n>:<datos>`. Un cliente ya publicado encuentra el
--   recibo y no escribe de nuevo. `n` crece sólo cuando la línea instala otra
--   cosa: si alguien corrige la ficha después, no se le pisa.
-- * `transition_mechanic_job_status` lo llama al dejar el trabajo FINALIZADO o
--   ENTREGADO (el mismo corte que exige el parche), en su transacción, y
--   devuelve `installed_bike_facts` con lo aplicado y lo que no se pudo. Cada
--   línea va en su propio bloque: una ficha que no acepta un dato se informa
--   y no impide terminar el trabajo. Su `40001` («el vínculo financiero
--   cambió») pasa a `PT409`, como en `20260928052000`.
-- * `sync_job_installed_bike_facts_v1` hace lo mismo para una línea corregida
--   en un trabajo ya terminado, al guardarlo. Lo que una línea escribió y ya
--   no respalda (pasó a otra bici o a la otra rueda, o se borró) no se deshace
--   solo —el recibo no guarda si el dato estaba confirmado ni de dónde venía,
--   y no se sabe cuál asignación era la equivocada—: vuelve como problema
--   mientras esa ficha lo siga diciendo con el origen de esa línea y nadie
--   haya escrito esa clave después (revisión del dueño, 2026-09-28). Un
--   guardado de la ficha por otro campo no lo apaga: el formulario manda la
--   ficha completa y conserva el origen `job_completion`; elegir el dato en
--   su campo lo deja `mechanic`. Toma el trabajo `for update`:
--   dos sincronizaciones a la vez calculaban la misma llave con otro valor
--   esperado y la segunda chocaba con el recibo de la primera.
-- * `patch_bike_technical_facts_v1`, con fuente `job_completion`, toma el
--   trabajo antes que la llave. La transición llega al parche con el trabajo
--   ya tomado; un cliente publicado que tomaba la llave y esperaba el trabajo
--   cerraba un ciclo con ella (revisión de Codex, 2026-09-28).
--
-- Lo que no entra a la ficha y lo que una línea ya no respalda no depende de
-- que la app alcance a mostrarlo: queda también en la historia de la bici
-- (`bike_events`, `severity = 'warning'`, fuente `installed_fact_notice`),
-- una vez por recibo, en la misma transacción (revisión del dueño,
-- 2026-09-28).
--
-- Depende de `20260928052000` (el parche avisa sus conflictos con PT409).
begin;

-- «36H en la rueda delantera»: como lo dice el taller.
create or replace function public.installed_bike_fact_label(p_key text, p_value jsonb)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select coalesce(p_value #>> '{}', '?') || 'H en la rueda '
    || case p_key when 'frontSpokeHoles' then 'delantera' else 'trasera' end;
$function$;

revoke all on function public.installed_bike_fact_label(text, jsonb)
  from public, anon, authenticated, service_role;

-- Un aviso en la historia de la bici, una sola vez por `p_notice_key`. Con
-- `p_required` (lo anota el disparador de una línea borrada o editada) un
-- aviso que no se puede anotar hace fallar a quien lo anota: esa línea no se
-- guarda sin su aviso. Sin él (la transición y la llamada que sigue al
-- guardado) el aviso es de mejor esfuerzo: si no entra, sigue en la
-- respuesta, y la llamada siguiente lo vuelve a calcular desde los recibos
-- (revisión del dueño, 2026-09-28).
drop function if exists public.record_installed_bike_fact_notice(
  uuid, uuid, uuid, text, text, text, text, jsonb);
create or replace function public.record_installed_bike_fact_notice(
  p_tenant_id uuid,
  p_bike_id uuid,
  p_job_id uuid,
  p_notice_key text,
  p_event_type text,
  p_title text,
  p_summary text,
  p_payload jsonb,
  p_required boolean
)
returns void
language plpgsql
set search_path to 'public'
as $function$
begin
  insert into public.bike_events (
    tenant_id, bike_id, job_id, event_type, event_category, severity,
    event_date, title, summary, source, payload, created_by
  )
  select p_tenant_id, p_bike_id, p_job_id, p_event_type, 'state', 'warning',
         clock_timestamp(), p_title, p_summary, 'installed_fact_notice',
         p_payload || jsonb_build_object('notice_key', p_notice_key),
         auth.uid()
   where not exists (
     select 1
       from public.bike_events e
      where e.tenant_id = p_tenant_id
        and e.bike_id = p_bike_id
        and e.source = 'installed_fact_notice'
        and e.payload->>'notice_key' = p_notice_key
   );
exception
  when others then
    if p_required then
      raise;
    end if;
end;
$function$;

revoke all on function public.record_installed_bike_fact_notice(uuid, uuid, uuid, text, text, text, text, jsonb, boolean)
  from public, anon, authenticated, service_role;

drop function if exists public.apply_job_installed_bike_facts_internal(uuid, uuid);
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
  v_job_bike_id uuid;
  v_job_bike_count integer;
  v_single_bike_id uuid;
  v_item record;
  v_position text;
  v_holes_text text;
  v_holes integer;
  v_key text;
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
  select j.bike_id
    into v_job_bike_id
    from public.mechanic_jobs j
   where j.id = p_job_id
     and j.tenant_id = p_tenant_id;

  select count(*)::integer, min(jb.bike_id::text)::uuid
    into v_job_bike_count, v_single_bike_id
    from public.mechanic_job_bikes jb
   where jb.job_id = p_job_id
     and jb.tenant_id = p_tenant_id;

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
       and i.service_configuration_data ? 'hole_count'
     -- Por bici, en el mismo orden en todo trabajo: dos trabajos con las
     -- mismas bicis no se toman una cada uno.
     order by jb.bike_id nulls last, i.created_at, i.id
  loop
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
    v_holes := v_holes_text::integer;
    v_key := case v_position
      when 'front' then 'frontSpokeHoles'
      else 'rearSpokeHoles'
    end;

    -- La bici de la línea; una línea de General es de la única bici del
    -- trabajo (o de la bici del trabajo, si no tiene filas de bicis).
    v_bike_id := case
      when v_item.job_bike_id is not null then v_item.line_bike_id
      when v_job_bike_count = 1 then v_single_bike_id
      when v_job_bike_count = 0 then v_job_bike_id
    end;
    if v_bike_id is null then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'key', v_key,
        'value', v_holes,
        'reason', 'line_without_bike'
      ));
      continue;
    end if;

    if v_holes not between 12 and 48 then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'bike_id', v_bike_id,
        'key', v_key,
        'value', v_holes,
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
      'value', v_holes
    ));

    v_facts_suffix := v_key || '=' || v_holes::text;
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
      perform 1
         from public.bikes b
        where b.id = v_bike_id
          and b.tenant_id = p_tenant_id
        for update;
      v_current := null;
      v_current_confirmed := false;
      select bp.technical_profile->'values'->v_key,
             coalesce(bp.technical_profile->'confirmed'->>v_key, 'false') = 'true'
        into v_current, v_current_confirmed
        from public.bike_profiles bp
       where bp.bike_id = v_bike_id
         and bp.tenant_id = p_tenant_id
       for update;

      v_receipt := public.patch_bike_technical_facts_v1(
        v_operation_key,
        v_bike_id,
        p_job_id,
        'job_completion',
        jsonb_build_array(jsonb_build_object(
          'key', v_key,
          'op', 'set',
          'value', v_holes,
          'expected', coalesce(v_current, 'null'::jsonb),
          'expected_confirmed', coalesce(v_current_confirmed, false)
        ))
      );
      v_applied := v_applied || jsonb_build_array(jsonb_build_object(
        'item_id', v_item.id,
        'item_name', v_item.product_name,
        'bike_id', v_bike_id,
        'key', v_key,
        'value', v_holes,
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
          'value', v_holes,
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
            public.installed_bike_fact_label(v_key, to_jsonb(v_holes)),
            coalesce(v_item.product_name, 'una línea'),
            sqlerrm),
          jsonb_build_object(
            'operation_key', v_operation_key,
            'item_id', v_item.id,
            'key', v_key,
            'value', v_holes,
            'code', sqlstate),
          p_notices_required);
    end;
  end loop;

  -- Lo que una línea de este trabajo escribió y ya no respalda: pasó a otra
  -- bici o a la otra rueda, cambió de servicio o se borró. Se toma lo último
  -- que cada línea escribió en cada bici y clave; si la ficha todavía lo dice
  -- con el origen de la línea (`job_completion`) y ningún recibo posterior
  -- escribió esa clave en esa bici, se informa para que el operador la
  -- corrija o la confirme. Confirmarla es elegir el dato en su campo de la
  -- ficha, que deja el origen `mechanic`; guardar la ficha por otro campo no
  -- la revisa (el formulario conserva el origen de lo que no se tocó).
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
        'bici (%s). Si esa rueda no se armó, corrige la ficha; si sí, vuelve a '
        'elegir el dato en su campo para confirmarlo.',
        public.installed_bike_fact_label(v_prior.key, v_prior.written),
        coalesce(v_prior.item_name, 'una línea que ya no está'),
        case
          when v_prior.previous is null or v_prior.previous = 'null'::jsonb
            then 'antes no tenía el dato'
          else 'antes: '
            || public.installed_bike_fact_label(v_prior.key, v_prior.previous)
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

-- Con fuente `job_completion`, el parche toma el trabajo antes que la llave
-- de la operación: el mismo orden que la transición, que llega aquí con el
-- trabajo ya tomado. Se inserta sobre la definición vigente (con PT409 desde
-- 20260928052000) y es reejecutable.
do $do$
declare
  v_fn regprocedure :=
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure;
  v_def text;
  v_anchor text := E'  perform pg_advisory_xact_lock(\n'
    || E'    hashtextextended(v_tenant_id::text || '':bike_fact_patch:'' || v_operation_key, 0)\n'
    || E'  );';
  v_block text := E'  -- Lo instalado toma el trabajo antes que la llave: la transición que lo\n'
    || E'  -- termina llega aquí con el trabajo tomado (20260928060000).\n'
    || E'  if p_source = ''job_completion'' then\n'
    || E'    perform 1\n'
    || E'      from public.mechanic_jobs j\n'
    || E'     where j.id = p_job_id\n'
    || E'       and j.tenant_id = v_tenant_id\n'
    || E'     for share;\n'
    || E'  end if;\n\n';
begin
  v_def := pg_get_functiondef(v_fn);
  if position('Lo instalado toma el trabajo antes que la llave' in v_def) > 0 then
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'patch_bike_technical_facts_v1 no tiene el lock de la operación esperado';
  end if;
  execute replace(v_def, v_anchor, v_block || v_anchor);
end;
$do$;

CREATE OR REPLACE FUNCTION public.transition_mechanic_job_status(p_job_id uuid, p_status_id uuid, p_operation_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '750ms'
AS $function$
declare
  v_preflight_tenant_id uuid;
  v_preflight_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_updated_job public.mechanic_jobs%rowtype;
  v_status public.job_statuses%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_event public.mechanic_job_status_transition_events%rowtype;
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_target_legacy_status text;
  v_request jsonb;
  v_response jsonb;
  v_changed boolean;
  v_now timestamptz;
  v_is_start boolean;
  v_is_complete boolean;
  v_is_delivered boolean;
  v_has_payment_evidence boolean := false;
  v_installed jsonb;
begin
  if p_job_id is null or p_status_id is null then
    raise exception 'El trabajo y el estado son obligatorios.'
      using errcode = '22004';
  end if;
  if v_operation_key = '' then
    raise exception 'El cambio de estado requiere una clave de operación.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'job_id', p_job_id,
    'status_id', p_status_id
  );

  -- Authorize from current job ownership before reading a receipt. A replay
  -- remains available after soft deletion because its committed result is
  -- immutable evidence, but a new command below rejects deleted work.
  select job.tenant_id, job.invoice_id
    into v_preflight_tenant_id, v_preflight_invoice_id
  from public.mechanic_jobs job
  where job.id = p_job_id;
  if not found then
    raise exception 'Trabajo no encontrado.' using errcode = 'P0002';
  end if;
  perform public.assert_workshop_rpc_tenant(v_preflight_tenant_id);

  select event.* into v_event
  from public.mechanic_job_status_transition_events event
  where event.tenant_id = v_preflight_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.job_id is distinct from p_job_id
       or v_event.to_status_id is distinct from p_status_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otro cambio de estado.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  -- Payment posting locks invoice before job. Follow that global order, then
  -- revalidate the preflight relationship so a concurrent link/unlink cannot
  -- redirect this transition to an invoice that was never serialized here.
  if v_preflight_invoice_id is not null then
    select invoice.* into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_preflight_invoice_id
      and invoice.tenant_id = v_preflight_tenant_id
    for update;
    if not found then
      raise exception 'La factura vinculada al trabajo no existe.'
        using errcode = '55000';
    end if;
  end if;

  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.tenant_id = v_preflight_tenant_id
    and job.deleted_at is null
  for update;
  if not found then
    raise exception 'Trabajo no encontrado o eliminado.' using errcode = 'P0002';
  end if;
  if v_job.invoice_id is distinct from v_preflight_invoice_id then
    -- PT409 y no 40001: PostgREST 14 reintenta un 40001 sin fin y el
    -- cliente recibe un 504 (20260928052000).
    raise exception 'El vínculo financiero del trabajo cambió durante la transición; vuelve a intentarlo.'
      using errcode = 'PT409';
  end if;

  -- Another request with the same key may have committed while this call was
  -- waiting for the job. Re-read the exact receipt under the serialized lock.
  select event.* into v_event
  from public.mechanic_job_status_transition_events event
  where event.tenant_id = v_job.tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.job_id is distinct from p_job_id
       or v_event.to_status_id is distinct from p_status_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otro cambio de estado.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select status.* into v_status
  from public.job_statuses status
  where status.id = p_status_id
    and status.tenant_id = v_job.tenant_id
    and status.is_active
  for share;
  if not found then
    raise exception 'El estado no existe, está inactivo o pertenece a otro negocio.'
      using errcode = '23514';
  end if;

  v_target_legacy_status := upper(btrim(v_status.code));
  if v_target_legacy_status = '' then
    raise exception 'El estado seleccionado no tiene un código operativo válido.'
      using errcode = '23514';
  end if;

  v_changed := v_job.status_id is distinct from v_status.id
    or v_job.status is distinct from v_target_legacy_status;

  -- An exact same-state command is a durable no-op receipt. It deliberately
  -- does not include status/status_id in an UPDATE, so no lifecycle,
  -- inventory or accounting trigger can run.
  if not v_changed then
    v_updated_job := v_job;
  else
    -- Covered warranty status changes can post or reverse their internal
    -- invoice. Fail closed on any settlement evidence while holding the
    -- invoice lock; no trigger is allowed to run before this guard succeeds.
    if (v_job.workflow_kind = 'warranty' or v_job.job_type = 'warranty')
       and v_job.warranty_outcome = 'covered' then
      if v_job.invoice_id is null or v_invoice.id is null then
        raise exception 'La garantía cubierta no tiene un respaldo financiero verificable; no se cambió su estado.'
          using errcode = '55000';
      end if;

      select
        lower(coalesce(v_invoice.status, '')) in ('paid', 'pagado', 'pagada')
        or coalesce(v_invoice.paid_amount, 0) > 0
        or exists (
          select 1
          from public.sales_payments payment
          where payment.tenant_id = v_job.tenant_id
            and payment.invoice_id = v_job.invoice_id
            and payment.deleted_at is null
            and coalesce(payment.amount, 0) > 0
        )
      into v_has_payment_evidence;

      if v_has_payment_evidence then
        raise exception 'La garantía cubierta tiene evidencia de pago. Corrige primero la factura desde el flujo financiero auditado.'
          using errcode = '55000';
      end if;
    end if;

    v_now := clock_timestamp();
    v_is_start := coalesce(v_status.triggers_start, false)
      or v_target_legacy_status = 'EN_CURSO';
    v_is_complete := coalesce(v_status.triggers_completion, false)
      or coalesce(v_status.triggers_delivery, false)
      or v_target_legacy_status in ('FINALIZADO', 'ENTREGADO');
    v_is_delivered := coalesce(v_status.triggers_delivery, false)
      or v_target_legacy_status = 'ENTREGADO';

    perform set_config('app.mechanic_job_status_rpc', 'true', true);
    update public.mechanic_jobs job
    set status_id = v_status.id,
        status = v_target_legacy_status,
        started_at = case
          when v_is_start then coalesce(job.started_at, v_now)
          else job.started_at
        end,
        completed_at = case
          when v_is_complete then coalesce(job.completed_at, v_now)
          else job.completed_at
        end,
        delivered_at = case
          when v_is_delivered then coalesce(job.delivered_at, v_now)
          else null
        end,
        updated_at = v_now
    where job.id = v_job.id
      and job.tenant_id = v_job.tenant_id
    returning job.* into v_updated_job;
    perform set_config('app.mechanic_job_status_rpc', '', true);
  end if;

  -- Lo que las líneas del trabajo dejaron instalado cambia la ficha de la bici
  -- en esta misma transacción (ítem 4, 2026-09-28). También al repetir el
  -- mismo estado terminado: es el reintento de lo que no llegó o de una línea
  -- corregida después. Lo que no se pudo escribir vuelve en la respuesta; no
  -- impide terminar el trabajo.
  if v_updated_job.status in ('FINALIZADO', 'ENTREGADO') then
    v_installed := public.apply_job_installed_bike_facts_internal(
      v_updated_job.tenant_id,
      v_updated_job.id
    );
  end if;

  v_response := jsonb_build_object(
    'job_id', v_updated_job.id,
    'status_id', v_updated_job.status_id,
    'status', v_updated_job.status,
    'changed', v_changed,
    'status_updated_at', v_updated_job.status_updated_at,
    'job', to_jsonb(v_updated_job),
    'installed_bike_facts', v_installed
  );

  insert into public.mechanic_job_status_transition_events (
    tenant_id,
    job_id,
    from_status_id,
    to_status_id,
    from_legacy_status,
    to_legacy_status,
    changed,
    actor_id,
    operation_key,
    request_snapshot,
    response_snapshot,
    occurred_at
  ) values (
    v_job.tenant_id,
    v_job.id,
    v_job.status_id,
    v_status.id,
    v_job.status,
    v_target_legacy_status,
    v_changed,
    auth.uid(),
    v_operation_key,
    v_request,
    v_response,
    clock_timestamp()
  ) returning * into v_event;

  perform set_config('app.mechanic_job_status_rpc', '', true);
  return to_jsonb(v_event)
    || v_response
    || jsonb_build_object('replay', false);
exception
  when others then
    perform set_config('app.mechanic_job_status_rpc', '', true);
    raise;
end;
$function$;

create or replace function public.sync_job_installed_bike_facts_v1(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
set lock_timeout to '750ms'
as $function$
declare
  v_tenant_id uuid;
  v_job public.mechanic_jobs%rowtype;
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

  -- El trabajo antes que la bici, como en la transición y en el parche, y
  -- `for update`: dos sincronizaciones a la vez calculan la misma llave, y la
  -- segunda, con la ficha ya cambiada, chocaría con el recibo de la primera.
  select job.*
    into v_job
    from public.mechanic_jobs job
   where job.id = p_job_id
     and job.tenant_id = v_tenant_id
     and job.deleted_at is null
   for update;
  if not found then
    raise exception 'Trabajo no encontrado o eliminado.' using errcode = 'P0002';
  end if;

  if v_job.status not in ('FINALIZADO', 'ENTREGADO') then
    return jsonb_build_object(
      'job_id', v_job.id,
      'finished', false,
      'applied', '[]'::jsonb,
      'problems', '[]'::jsonb
    );
  end if;

  return jsonb_build_object('job_id', v_job.id, 'finished', true)
    || public.apply_job_installed_bike_facts_internal(v_tenant_id, v_job.id);
end;
$function$;

revoke all on function public.sync_job_installed_bike_facts_v1(uuid)
  from public, anon, service_role;
grant execute on function public.sync_job_installed_bike_facts_v1(uuid)
  to authenticated;

commit;
