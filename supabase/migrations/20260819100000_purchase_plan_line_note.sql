-- La nota libre de una línea del plan.
--
-- **Qué la pide.** `handoff-t23/spec.json`, `frames[plan].with_lines`:
-- `line_disclosure: "Alternativa y nota (sustituir candidato, nota libre)"`.
-- El desplegable de la línea existía pero sólo **mostraba evidencia**; la nota
-- no tenía dónde guardarse, así que el operador no podía dejar dicho por qué
-- eligió ese candidato y no otro. Esa razón es justo lo que se pierde entre el
-- borrador y la compra.
--
-- **Por qué una columna y no un flujo append-only.** La preferencia comercial
-- de una necesidad vive en su propio flujo porque **varios** escritores tocan
-- la revisión de interpretación y el primero que la omita la borra
-- (`20260817210000`). Acá no ocurre: `purchase_plan_lines` tiene tres
-- escritores, todos en este mismo archivo de dominio —preparar, cambiar
-- cantidad, retirar—, y ninguno reescribe la fila entera: cada uno hace
-- `update ... set <sus columnas>`. Una columna más no puede caerse por omisión
-- porque nadie la copia hacia adelante. Y la nota no necesita historia: es lo
-- que el operador quiere leer **ahora**, no una serie temporal.
--
-- **Limpiar es explícito y no es lo mismo que no tocar.** `p_note` nulo o en
-- blanco borra la nota. Un no-op —escribir la misma nota— **consume su clave**
-- con `changed = false`: sin eso la clave quedaría libre para otra petición y
-- el replay dejaría de significar algo.
--
-- Forward-only. Ninguna función existente cambia.

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. La columna.
-- ───────────────────────────────────────────────────────────────────────────
alter table public.purchase_plan_lines
  add column if not exists note text;

alter table public.purchase_plan_lines
  drop constraint if exists purchase_plan_lines_note_check;
alter table public.purchase_plan_lines
  add constraint purchase_plan_lines_note_check check (
    note is null
    or (btrim(note) <> '' and octet_length(note) <= 1000)
  );

comment on column public.purchase_plan_lines.note is
  'Free note the operator leaves on a plan line: why this candidate and not another. Never blank -- clearing writes NULL. Required by handoff-t23 frames[plan].with_lines.line_disclosure.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. El ledger del plan aprende un hecho más.
-- ───────────────────────────────────────────────────────────────────────────
alter table public.purchase_plan_events
  drop constraint if exists purchase_plan_events_action_check;
alter table public.purchase_plan_events
  add constraint purchase_plan_events_action_check check (action in (
    'line_prepared',
    'line_removed',
    'line_quantity_changed',
    'line_note_changed',
    'plan_ready',
    'plan_cancelled',
    'conversion_prepared',
    'converted'
  ));

-- ───────────────────────────────────────────────────────────────────────────
-- 3. El comando, con la misma forma que su hermano de cantidad.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.set_purchase_plan_line_note_v1(
  p_plan_id uuid,
  p_expected_plan_version bigint,
  p_line_id uuid,
  p_note text,
  p_operation_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
set lock_timeout to '750ms'
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request jsonb;
  v_response jsonb;
  v_receipt public.purchase_plan_events%rowtype;
  v_plan public.purchase_plans%rowtype;
  v_line public.purchase_plan_lines%rowtype;
  v_groups jsonb;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_plan_id is null or p_expected_plan_version is null or p_line_id is null
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'El plan, versión, línea y clave son obligatorios.'
      using errcode = '22023';
  end if;
  if v_note is not null and octet_length(v_note) > 1000 then
    raise exception 'La nota de la línea no puede exceder 1000 bytes.'
      using errcode = '22023';
  end if;

  -- La nota entra al recibo **normalizada**, no cruda: si guardáramos el texto
  -- tal cual llegó, dos peticiones que sólo difieren en espacios se leerían
  -- como cambios distintos y el replay compararía contra algo que la fila
  -- nunca tuvo.
  v_request := jsonb_build_object(
    'plan_id', p_plan_id,
    'expected_plan_version', p_expected_plan_version,
    'line_id', p_line_id,
    'note', v_note
  );
  select event.* into v_receipt
  from public.purchase_plan_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'line_note_changed'
       or v_receipt.plan_id <> p_plan_id
       or v_receipt.line_id <> p_line_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro cambio del plan.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  -- Mismo orden de bloqueo que el resto del dominio: plan y luego línea. La
  -- necesidad no se toca acá —una nota no mueve cantidades ni elegibilidad—,
  -- así que no se bloquea: tomar un lock que no se necesita es cómo nacen los
  -- deadlocks entre dos comandos que se cruzan.
  select plan.* into v_plan
  from public.purchase_plans plan
  where plan.tenant_id = v_tenant_id and plan.id = p_plan_id
  for update;
  if not found then
    raise exception 'Plan no encontrado.' using errcode = 'P0002';
  end if;
  if v_plan.state <> 'draft' then
    raise exception 'Sólo un plan borrador puede editarse.' using errcode = '55000';
  end if;
  if v_plan.version <> p_expected_plan_version then
    raise exception 'El plan cambió; vuelve a cargarlo antes de guardar.'
      using errcode = '40001';
  end if;

  select line.* into v_line
  from public.purchase_plan_lines line
  where line.tenant_id = v_tenant_id
    and line.plan_id = v_plan.id
    and line.id = p_line_id
  for update;
  if not found then
    raise exception 'Línea del plan no encontrada.' using errcode = 'P0002';
  end if;
  if v_line.state <> 'active' then
    raise exception 'Sólo una línea activa puede llevar nota.'
      using errcode = '55000';
  end if;

  v_changed := v_line.note is distinct from v_note;
  if v_changed then
    update public.purchase_plan_lines line
    set note = v_note,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where line.tenant_id = v_tenant_id and line.id = v_line.id
    returning * into v_line;

    update public.purchase_plans plan
    set version = plan.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where plan.tenant_id = v_tenant_id and plan.id = v_plan.id
    returning * into v_plan;
  end if;

  select coalesce(jsonb_agg(to_jsonb(group_row)
    order by group_row.supplier_name, group_row.currency_code), '[]'::jsonb)
  into v_groups
  from public.purchase_plan_supplier_groups_v1 group_row
  where group_row.tenant_id = v_tenant_id
    and group_row.plan_id = v_plan.id;

  v_response := jsonb_build_object(
    'plan_id', v_plan.id,
    'plan_version', v_plan.version,
    'changed', v_changed,
    'plan', to_jsonb(v_plan),
    'line', to_jsonb(v_line),
    'supplier_groups', v_groups
  );
  insert into public.purchase_plan_events (
    tenant_id, plan_id, line_id, action, changed, actor_id,
    operation_key, request_snapshot, response_snapshot
  ) values (
    v_tenant_id, v_plan.id, v_line.id, 'line_note_changed', v_changed,
    v_actor_id, v_operation_key, v_request, v_response
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$function$;

revoke all on function public.set_purchase_plan_line_note_v1(
  uuid, bigint, uuid, text, text
) from public, anon;
grant execute on function public.set_purchase_plan_line_note_v1(
  uuid, bigint, uuid, text, text
) to authenticated;

comment on function public.set_purchase_plan_line_note_v1(
  uuid, bigint, uuid, text, text
) is
  'Sets or clears the free note on an active plan line. Replay-safe by operation_key; a no-op still consumes its key with changed=false. Blank note clears. Same optimistic-concurrency contract as update_purchase_plan_line_quantity_v1.';

commit;
