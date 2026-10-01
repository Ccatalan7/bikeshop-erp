-- Deployment status: NOT DEPLOYED
-- Las líneas del trabajo y lo que «Configurar» confirma de la bici se guardan
-- en una sola transacción, con un recibo (BIKE_WORKSHOP_MASTER_SCHEMA.md,
-- ítem 4).
--
-- Hasta aquí `_saveJob` escribía cada línea con su propio `insert`/`update`/
-- `delete` de PostgREST y, al final, mandaba a la ficha lo que confirmó
-- «Configurar» (`patch_bike_technical_facts_v1`). Tres problemas:
--
-- * Un corte a mitad dejaba la mitad de las líneas guardadas, y la ficha sin
--   el dato que salía de ellas (la bandeja lo retenía y lo resolvía después,
--   pero línea y ficha seguían siendo dos escrituras).
-- * Nada decía si las líneas habían cambiado desde que se abrió el
--   formulario: el guardado reescribía la fila completa de cada línea y
--   borraba las que no conocía, también las que otra persona acababa de
--   agregar.
-- * Un reintento tras una respuesta perdida volvía a insertar las líneas
--   nuevas.
--
-- `save_mechanic_job_lines_v1` recibe el juego completo de líneas del trabajo
-- y, en una transacción:
--
-- 1. Compara lo que el formulario vio (`p_seen_lines`: id y `updated_at` de
--    cada línea que cargó) con lo que hay. Una línea agregada, cambiada o
--    borrada por otro rechaza el guardado entero con `PT409`
--    (`job_lines_changed`) y nombra cada línea: el formulario la recarga en
--    vez de pisarla.
-- 2. Actualiza las líneas que cambiaron (sólo esas), inserta las nuevas y
--    borra las que el formulario quitó, en ese orden (el mismo del cliente:
--    una línea que reemplaza a otra instala antes de que la otra se vaya).
--    Los disparadores de siempre corren igual, incluido el que escribe lo
--    instalado en un trabajo terminado (`20260928070000`) y
--    `trg_auto_parse_item_description`, el único que crea las tareas de una
--    línea nueva desde la descripción de su producto o servicio: nacen en
--    esta transacción y el recibo las cubre. La app también las creaba
--    después de la respuesta, con otra regla (cada renglón, con su viñeta):
--    duplicaba las del disparador —32 nombres repetidos en 8 líneas de
--    producción al 2026-09-28— y un comando confirmado tras un reinicio
--    quedaba sin las suyas. Ya no las crea (revisiones del 2026-09-28).
-- 3. Escribe en la ficha, bici por bici, lo que confirmó «Configurar», con
--    `patch_bike_technical_facts_v1` y una llave derivada de la del comando.
--    Si la ficha cambió (`PT409`) o rechaza el dato, las líneas tampoco se
--    guardan; el error lleva `hint = bike_facts:<bici>` para que el formulario
--    sepa qué bici pedir reconfirmar. Un error pasajero sale sin esa pista.
-- 4. Guarda el recibo por `operation_key`. La misma llave con el mismo
--    contenido devuelve el recibo (`replayed = true`) sin escribir otra vez;
--    con otro contenido, se rechaza. `get_mechanic_job_line_save_v1` lo lee
--    sin escribir: la app respalda el comando en la bandeja del equipo
--    antes de enviarlo, y tras un corte pregunta por su llave antes de
--    reenviarlo.
--
-- Con `p_lines = null` (y `p_seen_lines = null`) no toca las líneas: es el
-- trabajo con pago, cuyas líneas están protegidas, que igual puede llevar lo
-- confirmado a la ficha.
--
-- La cabecera del trabajo viaja en el mismo comando (`p_header`, revisión del
-- 2026-09-28): antes el formulario reescribía la fila completa de
-- `mechanic_jobs` con los valores que había cargado —también los que no
-- tocó, como el técnico asignado o la prioridad cambiada desde la tabla— en
-- una escritura aparte, antes de las líneas. Ahora manda sólo los campos que
-- cambió, cada uno con el valor que vio (`{campo: {value, expected}}`, tal
-- como lo mandó el servidor). Si otra persona cambió ese mismo campo, nada se
-- guarda (`PT409`, `hint = job_header_changed`, `detail` con los campos). Los
-- campos son los que edita el formulario; los costos, la factura, el estado
-- y los tiempos del ciclo tienen su propio dueño. La cabecera va antes de las
-- líneas, como antes, y el descuento al final, cuando el subtotal ya es el
-- nuevo. El recibo trae la cabecera que quedó: es lo que el formulario vio
-- para el guardado siguiente.
--
-- Las bicis del trabajo también (`p_job_bikes`, revisiones de Codex del
-- 2026-09-28): el diagnóstico, lo pedido y las notas de cada una, su hoja de
-- diagnóstico y sus marcas. Antes el formulario las escribía por su cuenta
-- antes del comando, y uno rechazado (líneas o cabecera cambiadas por otro)
-- dejaba escrito el diagnóstico de la bici sin lo demás. Viajan sólo las que
-- cambian: la nueva con lo suyo; de la que estaba, cada campo cambiado con
-- lo que se vio al cargar (si otro lo cambió, `PT409 job_bikes_changed`,
-- como la cabecera); la que sale, con `remove` y lo que se vio de ella (si
-- otro la cambió no se borra), y se borra al final con sus líneas en
-- cascada. Una que no viene no se toca: otra persona pudo
-- agregarla. Con la factura pagada no se agregan ni quitan, y su orden y sus
-- marcas no cambian. Una línea de una bici nueva la nombra por su llave
-- (`job_bike_key`) y el recibo dice qué id tomó cada una, con lo que quedó.
--
-- La factura también (`p_invoice`, 2026-09-28): la crea o la sincroniza al
-- final, en la misma transacción que el recibo, y el recibo dice qué pasó
-- (`created`, `synced`, `protected`, `posted`, `none` o `failed`). Con la
-- factura confirmada sin pagos, lo que cambiaría lo que se cobra se rechaza
-- antes de escribir (`55000`, `hint = invoice_posted`): se corrige desde la
-- factura. Un error pasajero de la factura deshace todo (`55P03`); uno del
-- dato deja el guardado con `failed`, y la repetición de la llave o
-- `continue_mechanic_job_invoice_v1` la intentan otra vez sin otro Guardar.
--
-- Locks: factura (si hay) → líneas del trabajo, por id → trabajo `for
-- update` → bicis del trabajo, por id → bici → ficha → llave. Las bicis van
-- después del trabajo porque una línea escrita por su cuenta toma el trabajo
-- en su guardia de pago y su bici después, en el disparador de costos (línea
-- → trabajo → bici). Las líneas van antes que el trabajo porque así las
-- toma cualquier escritura de una línea: su disparador de costos actualiza el
-- trabajo después. Con el trabajo primero, un borrado desde la tabla de
-- trabajos que tenía la línea y esperaba el trabajo cerraba un deadlock con
-- este comando (reproducido con dos sesiones, revisión de Codex del
-- 2026-09-28). La transición de estado toma factura → trabajo y no toca
-- líneas. Las conversiones de cotización y la clasificación del ingreso toman
-- trabajo → líneas: con ellas el cruce sigue siendo posible y Postgres corta
-- una. La llave del comando sólo la comparte un reintento de sí mismo.
begin;

create table if not exists public.mechanic_job_line_saves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_key text not null,
  payload_hash text not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  result_snapshot jsonb not null,
  created_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key)
);

comment on table public.mechanic_job_line_saves is
  'Recibos del guardado de líneas del trabajo con su ficha (save_mechanic_job_lines_v1). Evidencia del comando y respuesta de un reintento, no una segunda verdad: las líneas viven en mechanic_job_items y la ficha en bike_profiles.';

create index if not exists idx_mechanic_job_line_saves_job
  on public.mechanic_job_line_saves(tenant_id, job_id, completed_at desc);

alter table public.mechanic_job_line_saves enable row level security;

drop policy if exists mechanic_job_line_saves_select
  on public.mechanic_job_line_saves;
create policy mechanic_job_line_saves_select
  on public.mechanic_job_line_saves
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

revoke select, insert, update, delete
  on public.mechanic_job_line_saves
  from public, anon, authenticated;

-- El parche de la ficha toma el trabajo antes que la bici con cualquier
-- fuente, no sólo con `job_completion`: este comando lo llama con el trabajo
-- tomado, y una llamada suelta con `service_wizard` que tomara la bici
-- primero cerraría un ciclo con él (revisión de Codex, 2026-09-28). Se edita
-- sobre la definición vigente (20260928060000) y es reejecutable.
do $do$
declare
  v_fn regprocedure :=
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure;
  v_def text;
  v_old text := E'  if p_source = ''job_completion'' then\n'
    || E'    perform 1\n'
    || E'      from public.mechanic_jobs j\n'
    || E'     where j.id = p_job_id\n'
    || E'       and j.tenant_id = v_tenant_id\n'
    || E'     for share;\n'
    || E'  end if;\n';
  v_new text := E'  -- Con cualquier fuente, el trabajo antes que la bici: el guardado de\n'
    || E'  -- líneas llega con el trabajo tomado (20260928080000).\n'
    || E'  perform 1\n'
    || E'    from public.mechanic_jobs j\n'
    || E'   where j.id = p_job_id\n'
    || E'     and j.tenant_id = v_tenant_id\n'
    || E'   for share;\n';
begin
  v_def := pg_get_functiondef(v_fn);
  if position('Con cualquier fuente, el trabajo antes que la bici' in v_def) > 0 then
    return;
  end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'patch_bike_technical_facts_v1 no tiene el lock del trabajo esperado';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$do$;

-- Los costos por bici de una línea que cambia de bici: el disparador sólo
-- recalculaba la bici nueva y la anterior se quedaba con el costo de la
-- línea (segunda revisión de Codex, 2026-09-28; el comando deja cambiar
-- `job_bike_id`). Es la definición de producción, con su `search_path`,
-- más la bici anterior.
create or replace function public.recalculate_job_bike_costs()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_job_bike_ids uuid[];
  v_job_bike_id uuid;
  v_parts_cost numeric(12,2);
  v_labor_cost numeric(12,2);
begin
  -- 🔄 CIRCULAR SYNC GUARD
  if current_setting('app.syncing_invoice_to_job', true) = 'true' or
     current_setting('app.syncing_job_to_invoice', true) = 'true' then
    return coalesce(NEW, OLD);
  end if;

  if TG_OP = 'DELETE' then
    v_job_bike_ids := array[OLD.job_bike_id];
  elsif TG_OP = 'INSERT' then
    v_job_bike_ids := array[NEW.job_bike_id];
  else
    v_job_bike_ids := array[OLD.job_bike_id, NEW.job_bike_id];
  end if;

  for v_job_bike_id in
    select distinct changed.id
      from unnest(v_job_bike_ids) as changed(id)
     where changed.id is not null
     order by changed.id
  loop
    select coalesce(sum(case when item_type = 'product' or item_type is null then total_price else 0 end), 0),
           coalesce(sum(case when item_type = 'service' then total_price else 0 end), 0)
      into v_parts_cost, v_labor_cost
      from mechanic_job_items
     where job_bike_id = v_job_bike_id;
    update mechanic_job_bikes
       set parts_cost = v_parts_cost,
           labor_cost = v_labor_cost,
           subtotal = v_parts_cost + v_labor_cost,
           updated_at = now()
     where id = v_job_bike_id;
  end loop;
  return coalesce(NEW, OLD);
end;
$function$;

-- Qué protege la factura vinculada de un trabajo, en un solo lugar: `paid`
-- con pagos (el mismo predicado que las guardias de pago), `posted` si está
-- confirmada (fuera de borrador, enviada, emitida o anulada: ya descontó
-- stock y tiene su asiento) o tiene una nota de crédito contabilizada (cuya
-- guardia no deja cambiar sus líneas), y null si se puede sincronizar desde
-- el trabajo. La usan el comando, la factura del comando, las dos guardias de
-- escritura directa y `sync_job_to_invoice` (revisión de Codex del
-- 2026-09-28: la guardia vivía sólo en el comando, y Tareas o un Guardar sin
-- cambios seguían cambiando una factura confirmada).
create or replace function public.mechanic_job_invoice_lock_internal(
  p_tenant_id uuid,
  p_invoice_id uuid
)
returns text
language sql
stable
set search_path to 'public'
as $function$
  select case
    when invoice.id is null then null
    when lower(coalesce(invoice.status, '')) in ('paid', 'pagado', 'pagada')
         or coalesce(invoice.paid_amount, 0) > 0
         or exists (
           select 1
             from public.sales_payments payment
            where payment.invoice_id = invoice.id
              and payment.tenant_id = invoice.tenant_id
              and payment.deleted_at is null
              and coalesce(payment.amount, 0) > 0
         ) then 'paid'
    when lower(coalesce(invoice.status, 'draft')) <> all (array[
           'draft', 'borrador', 'sent', 'enviado', 'enviada', 'issued',
           'emitido', 'emitida', 'cancelled', 'cancelado', 'cancelada',
           'anulado', 'anulada'
         ])
         or exists (
           select 1
             from public.sales_credit_notes note
            where note.sales_invoice_id = invoice.id
              and note.tenant_id = invoice.tenant_id
              and note.status = 'posted'
         ) then 'posted'
  end
  from (select 1) as one
  left join public.sales_invoices invoice
    on invoice.id = p_invoice_id
   and invoice.tenant_id = p_tenant_id
$function$;

revoke all on function public.mechanic_job_invoice_lock_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- La factura del trabajo al día: la decisión que tenía el botón Guardar, en
-- un solo lugar para el comando, su repetición y la continuación
-- (`continue_mechanic_job_invoice_v1`). Toma factura → trabajo, el mismo
-- orden del comando (que ya los tiene), y vuelve a comprobar el vínculo con
-- los dos tomados.
--
-- * Cotización: no tiene factura (`none`).
-- * Con pagos: `sync_job_to_invoice` es un no-op comercial (`protected`).
-- * Confirmada sin pagos, o con una nota de crédito contabilizada (cuya
--   guardia rechaza cambiar sus líneas): ya descontó stock y tiene su asiento, y
--   `sync_job_to_invoice` escribe sus líneas y su total con la marca
--   (`app.syncing_job_to_invoice`) que hace saltar ese recálculo. No se toca
--   desde aquí (`posted`); el comando rechaza antes, sin escribir, lo que
--   cambiaría lo que se cobra, y eso se corrige desde la factura, que rehace
--   stock y asiento y lo proyecta al trabajo (revisiones del 2026-09-28).
-- * Borrador, enviada, emitida o anulada: se sincroniza (`synced`).
-- * Sin factura, una venta o un servicio facturable la crea
--   (`create_billable_invoice_from_mechanic_job`, que con una ya vinculada
--   devuelve ésa: no hay dos) (`created`).
--
-- Un error pasajero (lock, deadlock, serialización, conexión, recursos) sale
-- como `55P03` y deshace todo lo de su transacción: el guardado entero vuelve
-- a la bandeja y se reintenta junto. Nunca como `40001`, que PostgREST
-- reintenta sin fin. Un error del dato o de una regla (el ingreso sin
-- clasificar, una bici que falta) deja lo demás guardado y vuelve como
-- `failed` con su código: la continuación lo intenta otra vez sin otro
-- Guardar (revisión del 2026-09-28).
create or replace function public.mechanic_job_invoice_step_internal(
  p_tenant_id uuid,
  p_job_id uuid
)
returns jsonb
language plpgsql
set search_path to 'public'
as $function$
declare
  v_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_lock text;
  v_action text := 'none';
  v_error jsonb;
  v_state text;
  v_message text;
begin
  select j.invoice_id
    into v_invoice_id
    from public.mechanic_jobs j
   where j.id = p_job_id
     and j.tenant_id = p_tenant_id
     and j.deleted_at is null;
  if not found then
    return jsonb_build_object('action', 'none', 'invoice_id', null, 'error', null);
  end if;

  if v_invoice_id is not null then
    perform 1
      from public.sales_invoices invoice
     where invoice.id = v_invoice_id
       and invoice.tenant_id = p_tenant_id
     for update;
  end if;

  select *
    into v_job
    from public.mechanic_jobs j
   where j.id = p_job_id
     and j.tenant_id = p_tenant_id
     and j.deleted_at is null
   for update;
  if not found then
    return jsonb_build_object('action', 'none', 'invoice_id', null, 'error', null);
  end if;
  if v_job.invoice_id is distinct from v_invoice_id then
    raise exception 'La factura del trabajo cambió mientras se hacía; se vuelve a intentar.'
      using errcode = '55P03', hint = 'invoice_retry';
  end if;

  v_lock := public.mechanic_job_invoice_lock_internal(p_tenant_id, v_invoice_id);

  begin
    if v_job.workflow_kind = 'quotation' or v_job.job_type = 'quotation' then
      v_action := 'none';
    elsif v_lock = 'paid' then
      v_action := 'protected';
    elsif v_lock = 'posted' then
      v_action := 'posted';
    elsif v_invoice_id is not null then
      perform public.sync_job_to_invoice(p_job_id);
      v_action := 'synced';
    elsif v_job.workflow_kind = 'sale'
          or (v_job.workflow_kind = 'service'
              and v_job.job_type in ('service', 'item_service')) then
      perform public.create_billable_invoice_from_mechanic_job(p_job_id);
      v_action := 'created';
    end if;
  exception when others then
    get stacked diagnostics
      v_state = returned_sqlstate,
      v_message = message_text;
    if v_state in ('40001', '40P01', '55P03')
       or left(v_state, 2) in ('08', '53', '57') then
      raise exception 'La factura del trabajo está tomada por otra operación; se vuelve a intentar.'
        using errcode = '55P03',
              detail = jsonb_build_object('code', v_state, 'message', v_message)::text,
              hint = 'invoice_retry';
    end if;
    v_action := 'failed';
    v_error := jsonb_build_object('code', v_state, 'message', v_message);
  end;

  return jsonb_build_object(
    'action', v_action,
    'invoice_id', (select j.invoice_id
                     from public.mechanic_jobs j
                    where j.id = p_job_id
                      and j.tenant_id = p_tenant_id),
    'error', v_error
  );
end;
$function$;

revoke all on function public.mechanic_job_invoice_step_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Las formas anteriores (sin cabecera, sin bicis del trabajo) nunca se
-- desplegaron.
drop function if exists public.save_mechanic_job_lines_v1(
  text, uuid, jsonb, jsonb, jsonb
);
drop function if exists public.save_mechanic_job_lines_v1(
  text, uuid, jsonb, jsonb, jsonb, jsonb
);
drop function if exists public.save_mechanic_job_lines_v1(
  text, uuid, jsonb, jsonb, jsonb, jsonb, jsonb
);

create or replace function public.save_mechanic_job_lines_v1(
  p_operation_key text,
  p_job_id uuid,
  p_seen_lines jsonb,
  p_lines jsonb,
  p_bike_facts jsonb,
  p_header jsonb default null,
  p_job_bikes jsonb default null,
  p_invoice boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_active_profile_count integer;
  v_tenant_id uuid;
  v_operation_key text := nullif(btrim(p_operation_key), '');
  v_operation_id uuid := gen_random_uuid();
  v_payload_hash text;
  v_receipt public.mechanic_job_line_saves%rowtype;
  v_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_entry jsonb;
  v_line jsonb;
  v_row public.mechanic_job_items%rowtype;
  v_current record;
  v_seen jsonb := '{}'::jsonb;
  v_seen_id text;
  v_conflicts jsonb := '[]'::jsonb;
  v_client_keys text[] := array[]::text[];
  v_line_keys jsonb := '{}'::jsonb;
  v_current_ids uuid[] := array[]::uuid[];
  v_kept_ids uuid[] := array[]::uuid[];
  v_line_id uuid;
  v_inserted integer := 0;
  v_tasks_created integer := 0;
  v_updated integer := 0;
  v_deleted integer := 0;
  v_count integer;
  v_bike_ids uuid[] := array[]::uuid[];
  v_bike_id uuid;
  v_fact_result jsonb;
  v_fact_results jsonb := '[]'::jsonb;
  v_state text;
  v_message text;
  v_detail text;
  v_lines_result jsonb;
  v_result jsonb;
  -- Lo que el formulario edita de la cabecera.
  v_header_columns constant text[] := array[
    'customer_id', 'bike_id', 'job_type', 'workflow_kind', 'intake_kind',
    'mode_needs_review', 'mode_review_reason', 'subject_id', 'subject_notes',
    'warranty_outcome', 'quotation_status', 'quotation_valid_until',
    'priority', 'arrival_date', 'deadline', 'client_request', 'diagnosis',
    'work_performed', 'notes', 'estimated_duration_hours',
    'actual_labor_hours', 'is_warranty_job', 'requires_approval',
    'image_urls', 'discount_amount'
  ];
  -- Los que quedan fijos con la factura pagada: los mismos que el formulario
  -- deja fuera (`mechanicJobPaymentProtectedUpdatePayload`).
  v_paid_protected_columns constant text[] := array[
    'customer_id', 'bike_id', 'job_type', 'workflow_kind', 'intake_kind',
    'mode_needs_review', 'mode_review_reason', 'subject_id', 'subject_notes',
    'warranty_outcome', 'quotation_status', 'quotation_valid_until',
    'is_warranty_job', 'requires_approval', 'discount_amount'
  ];
  v_paid_fields jsonb;
  -- Lo que el formulario escribe de cada bici del trabajo. El estado, las
  -- fotos, la aprobación con fecha y los costos tienen su propio dueño.
  v_job_bike_columns constant text[] := array[
    'bike_id', 'order_index', 'diagnosis', 'work_requested', 'work_performed',
    'technician_notes', 'diagnosis_sheet_key', 'diagnosis_sheet_data',
    'diagnosis_sheet_updated_at', 'is_warranty_work', 'requires_approval',
    'approved_by_customer'
  ];
  -- Lo que se manda de una bici además de sus columnas.
  v_job_bike_meta constant text[] := array[
    'client_key', 'id', 'bike_id', 'remove', 'expected'
  ];
  -- Lo que no cambia en una bici de un trabajo con la factura pagada.
  v_job_bike_paid_columns constant text[] := array[
    'order_index', 'is_warranty_work', 'requires_approval',
    'approved_by_customer'
  ];
  v_job_bike jsonb;
  v_job_bike_keys jsonb := '{}'::jsonb;
  v_job_bike_client_keys text[] := array[]::text[];
  v_job_bike_line_keys text[] := array[]::text[];
  v_job_bike_sent_ids uuid[] := array[]::uuid[];
  v_removed_job_bike_ids uuid[] := array[]::uuid[];
  v_current_job_bike_ids uuid[] := array[]::uuid[];
  v_job_bike_conflicts jsonb := '[]'::jsonb;
  v_job_bike_paid jsonb := '[]'::jsonb;
  v_job_bike_old public.mechanic_job_bikes%rowtype;
  v_job_bike_expected public.mechanic_job_bikes%rowtype;
  v_job_bike_new public.mechanic_job_bikes%rowtype;
  v_invoice_lock text;
  v_invoice_paid boolean := false;
  v_invoice_posted boolean := false;
  v_invoice_number text;
  v_posted_changes jsonb := '[]'::jsonb;
  v_invoice_result jsonb;
  v_job_bike_set text;
  v_job_bike_id uuid;
  v_job_bikes_result jsonb;
  v_job_bikes_inserted integer := 0;
  v_job_bikes_updated integer := 0;
  v_job_bikes_deleted integer := 0;
  v_header jsonb := coalesce(p_header, '{}'::jsonb);
  v_header_expected public.mechanic_jobs%rowtype;
  v_header_new public.mechanic_jobs%rowtype;
  v_header_conflicts jsonb := '[]'::jsonb;
  v_header_set text;
  v_header_result jsonb;
  v_column text;
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

  if not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  -- La llave de la ficha se deriva de ésta y no puede pasar de 128.
  if v_operation_key is null or length(v_operation_key) > 80 then
    raise exception 'A valid job line save operation key is required'
      using errcode = '22023';
  end if;

  if p_job_id is null then
    raise exception 'Job id is required' using errcode = '22023';
  end if;

  if (p_lines is null) <> (p_seen_lines is null) then
    raise exception 'Lines travel with the lines the form loaded'
      using errcode = '22023';
  end if;

  if p_bike_facts is null
     or jsonb_typeof(p_bike_facts) <> 'array'
     or jsonb_array_length(p_bike_facts) > 16 then
    raise exception 'Bike facts must be an array of at most 16 bicycles'
      using errcode = '22023';
  end if;

  if jsonb_typeof(v_header) <> 'object' then
    raise exception 'The job header must be an object of changed fields'
      using errcode = '22023';
  end if;
  for v_column, v_entry in select key, value from jsonb_each(v_header)
  loop
    if not (v_column = any (v_header_columns))
       or jsonb_typeof(v_entry) <> 'object'
       or not (v_entry ? 'value' and v_entry ? 'expected')
       or exists (
         select 1 from jsonb_object_keys(v_entry) as entry_key
          where entry_key not in ('value', 'expected')
       ) then
      raise exception 'Header field % is not one the form edits, or lacks value and expected', v_column
        using errcode = '22023';
    end if;
  end loop;

  if p_lines is null
     and jsonb_array_length(p_bike_facts) = 0
     and v_header = '{}'::jsonb
     and coalesce(p_job_bikes, '[]'::jsonb) = '[]'::jsonb then
    raise exception 'Nothing to save' using errcode = '22023';
  end if;

  -- Las bicis del trabajo, sólo las que cambian: una nueva con todo lo suyo;
  -- de una que estaba, cada campo cambiado con el valor que se vio al cargar
  -- (`expected`), como la cabecera; y la que sale, con `remove`. Una bici que
  -- no viene no se toca: otra persona pudo agregarla mientras tanto (segunda
  -- revisión de Codex, 2026-09-28). La línea de una bici nueva la nombra por
  -- la llave de la bici (`job_bike_key`).
  if p_job_bikes is not null then
    if jsonb_typeof(p_job_bikes) <> 'array'
       or jsonb_array_length(p_job_bikes) > 16 then
      raise exception 'Job bikes must be an array of at most 16 bicycles'
        using errcode = '22023';
    end if;
    for v_job_bike in select value from jsonb_array_elements(p_job_bikes)
    loop
      if jsonb_typeof(v_job_bike) <> 'object'
         or not (v_job_bike ? 'client_key' and v_job_bike ? 'bike_id')
         or exists (
           select 1 from jsonb_object_keys(v_job_bike) as bike_key
            where bike_key <> all (v_job_bike_meta || v_job_bike_columns)
         ) then
        raise exception 'Each job bike needs client_key and bike_id, and only job bike fields'
          using errcode = '22023';
      end if;
      if nullif(btrim(v_job_bike->>'client_key'), '') is null
         or length(v_job_bike->>'client_key') > 80
         or (v_job_bike->>'client_key') = any (v_job_bike_client_keys) then
        raise exception 'Each job bike needs its own client_key'
          using errcode = '22023';
      end if;
      v_job_bike_client_keys :=
        v_job_bike_client_keys || (v_job_bike->>'client_key');
      perform (v_job_bike->>'bike_id')::uuid;
      v_job_bike_id := nullif(v_job_bike->>'id', '')::uuid;
      if v_job_bike_id is not null then
        if v_job_bike_id = any (v_job_bike_sent_ids || v_removed_job_bike_ids) then
          raise exception 'Job bike % appears twice', v_job_bike_id
            using errcode = '22023';
        end if;
      end if;
      if v_job_bike ? 'remove' then
        -- Sale con lo que se vio de ella: si otro la cambió, no se borra.
        if v_job_bike->'remove' <> 'true'::jsonb
           or v_job_bike_id is null
           or jsonb_typeof(v_job_bike->'expected') is distinct from 'object'
           or exists (
             select 1 from jsonb_object_keys(v_job_bike) as bike_key
              where bike_key not in ('client_key', 'id', 'bike_id', 'remove', 'expected')
           )
           or exists (
             select 1 from jsonb_object_keys(v_job_bike->'expected') as seen_key
              where seen_key <> all (v_job_bike_columns)
           ) then
          raise exception 'A job bike that leaves carries its id, remove = true and what was seen of it'
            using errcode = '22023';
        end if;
        if p_lines is null then
          raise exception 'A job whose lines stay as they are keeps its bicycles'
            using errcode = '22023';
        end if;
        v_removed_job_bike_ids := v_removed_job_bike_ids || v_job_bike_id;
      elsif v_job_bike_id is not null then
        -- Cada campo que manda, con lo que vio; nada visto sin su campo.
        if jsonb_typeof(v_job_bike->'expected') is distinct from 'object'
           or exists (
             select 1 from jsonb_object_keys(v_job_bike) as bike_key
              where bike_key <> all (v_job_bike_meta)
                and not ((v_job_bike->'expected') ? bike_key)
           )
           or exists (
             select 1 from jsonb_object_keys(v_job_bike->'expected') as seen_key
              where not (v_job_bike ? seen_key)
                 or seen_key = any (v_job_bike_meta)
           ) then
          raise exception 'A job bike already in the job sends each changed field with the value it saw'
            using errcode = '22023';
        end if;
        v_job_bike_sent_ids := v_job_bike_sent_ids || v_job_bike_id;
        v_job_bike_line_keys :=
          v_job_bike_line_keys || (v_job_bike->>'client_key');
      else
        if p_lines is null then
          raise exception 'A job whose lines stay as they are keeps its bicycles'
            using errcode = '22023';
        end if;
        if v_job_bike ? 'expected' then
          raise exception 'A new job bike has nothing it saw'
            using errcode = '22023';
        end if;
        v_job_bike_line_keys :=
          v_job_bike_line_keys || (v_job_bike->>'client_key');
      end if;
    end loop;
  end if;

  -- Forma de todo, antes de tocar nada.
  if p_seen_lines is not null then
    if jsonb_typeof(p_seen_lines) <> 'array'
       or jsonb_array_length(p_seen_lines) > 500 then
      raise exception 'Seen lines must be an array of at most 500 lines'
        using errcode = '22023';
    end if;
    for v_entry in select value from jsonb_array_elements(p_seen_lines)
    loop
      if jsonb_typeof(v_entry) <> 'object'
         or not (v_entry ? 'id' and v_entry ? 'updated_at')
         or exists (
           select 1 from jsonb_object_keys(v_entry) as entry_key
            where entry_key not in ('id', 'updated_at')
         ) then
        raise exception 'Each seen line needs id and updated_at, and nothing else'
          using errcode = '22023';
      end if;
      v_seen_id := ((v_entry->>'id')::uuid)::text;
      perform (v_entry->>'updated_at')::timestamptz;
      if v_seen ? v_seen_id then
        raise exception 'Seen line % appears twice', v_seen_id
          using errcode = '22023';
      end if;
      v_seen := v_seen || jsonb_build_object(v_seen_id, v_entry->>'updated_at');
    end loop;
  end if;

  if p_lines is not null then
    if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 500 then
      raise exception 'Lines must be an array of at most 500 lines'
        using errcode = '22023';
    end if;
    for v_line in select value from jsonb_array_elements(p_lines)
    loop
      -- Lo que el formulario escribe de una línea. El total lo calcula la base
      -- y la fecha de creación, el id de las nuevas y el taller los pone ella.
      if jsonb_typeof(v_line) <> 'object'
         or not (v_line ? 'client_key' and v_line ? 'product_name')
         or exists (
           select 1 from jsonb_object_keys(v_line) as line_key
            where line_key <> all (array[
              'client_key', 'id', 'job_bike_id', 'product_id',
              'service_product_id', 'product_name', 'product_sku', 'quantity',
              'unit_price', 'notes', 'service_configuration_data', 'item_type',
              'system_key', 'component_slot_key', 'location_key',
              'intervention_type', 'creates_lifecycle', 'job_bike_key'
            ]::text[])
         ) then
        raise exception 'Each line needs client_key and product_name, and only line fields'
          using errcode = '22023';
      end if;
      if nullif(btrim(v_line->>'client_key'), '') is null
         or length(v_line->>'client_key') > 80
         or (v_line->>'client_key') = any (v_client_keys) then
        raise exception 'Each line needs its own client_key'
          using errcode = '22023';
      end if;
      v_client_keys := v_client_keys || (v_line->>'client_key');
      if coalesce(jsonb_typeof(v_line->'service_configuration_data'), 'null')
         not in ('object', 'null') then
        raise exception 'A line configuration must be an object'
          using errcode = '22023';
      end if;
      if v_line ? 'job_bike_key'
         and (coalesce(v_line->'job_bike_id', 'null'::jsonb) <> 'null'::jsonb
              or not ((v_line->>'job_bike_key') = any (v_job_bike_line_keys))) then
        raise exception 'A line names its bicycle by job_bike_id or by the key of a job bike in this save'
          using errcode = '22023';
      end if;
      if coalesce(v_line->'id', 'null'::jsonb) <> 'null'::jsonb then
        v_line_id := (v_line->>'id')::uuid;
        -- Sólo se reescribe una línea que el formulario cargó: una de otro
        -- trabajo, o una que nunca vio, no se toca por id.
        if not (v_seen ? v_line_id::text) then
          raise exception 'Line % is not among the lines the form loaded', v_line_id
            using errcode = '22023';
        end if;
        if v_line_id = any (v_kept_ids) then
          raise exception 'Line % appears twice', v_line_id
            using errcode = '22023';
        end if;
        v_kept_ids := v_kept_ids || v_line_id;
      end if;
    end loop;
  end if;

  for v_entry in select value from jsonb_array_elements(p_bike_facts)
  loop
    if jsonb_typeof(v_entry) <> 'object'
       or not (v_entry ? 'bike_id' and v_entry ? 'facts')
       or exists (
         select 1 from jsonb_object_keys(v_entry) as entry_key
          where entry_key not in ('bike_id', 'facts')
       ) then
      raise exception 'Each bike fact entry needs bike_id and facts, and nothing else'
        using errcode = '22023';
    end if;
    v_bike_id := (v_entry->>'bike_id')::uuid;
    if v_bike_id = any (v_bike_ids) then
      raise exception 'Bicycle % appears twice', v_bike_id
        using errcode = '22023';
    end if;
    v_bike_ids := v_bike_ids || v_bike_id;
  end loop;

  v_payload_hash := encode(extensions.digest(jsonb_build_object(
    'job_id', p_job_id,
    'seen_lines', p_seen_lines,
    'lines', p_lines,
    'bike_facts', p_bike_facts,
    'header', v_header,
    'job_bikes', p_job_bikes,
    'invoice', coalesce(p_invoice, false)
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant_id::text || ':job_line_save:' || v_operation_key, 0)
  );

  select *
    into v_receipt
    from public.mechanic_job_line_saves
   where tenant_id = v_tenant_id
     and operation_key = v_operation_key;

  if found then
    if v_receipt.payload_hash is distinct from v_payload_hash then
      raise exception 'Job line save key was already used with different content'
        using errcode = 'integrity_constraint_violation';
    end if;
    -- Lo guardado ya está; una factura que quedó en `failed` se intenta otra
    -- vez (revisión del 2026-09-28: la repetición devolvía el fallo y, sin
    -- otro Guardar, la factura quedaba pendiente para siempre).
    if coalesce(p_invoice, false)
       and v_receipt.result_snapshot->'invoice'->>'action' = 'failed' then
      v_invoice_result := public.mechanic_job_invoice_step_internal(
        v_tenant_id, p_job_id);
      update public.mechanic_job_line_saves
         set result_snapshot = jsonb_set(
               result_snapshot, '{invoice}', v_invoice_result)
       where id = v_receipt.id
       returning * into v_receipt;
    end if;
    return v_receipt.result_snapshot || jsonb_build_object('replayed', true);
  end if;

  -- El pago asienta factura antes que trabajo: el mismo orden que la
  -- transición, y se revalida el vínculo ya con los dos tomados.
  select j.invoice_id
    into v_invoice_id
    from public.mechanic_jobs j
   where j.id = p_job_id
     and j.tenant_id = v_tenant_id
     and j.deleted_at is null;

  if not found then
    raise exception 'Trabajo no encontrado o eliminado.' using errcode = 'P0002';
  end if;

  if v_invoice_id is not null then
    perform 1
      from public.sales_invoices invoice
     where invoice.id = v_invoice_id
       and invoice.tenant_id = v_tenant_id
     for update;
  end if;

  -- Las líneas antes que el trabajo (ver el encabezado).
  if p_lines is not null then
    for v_current in
      select i.id, i.updated_at
        from public.mechanic_job_items i
       where i.tenant_id = v_tenant_id
         and i.job_id = p_job_id
       order by i.id
       for update
    loop
      v_current_ids := v_current_ids || v_current.id;
      if not (v_seen ? v_current.id::text) then
        v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
          'line_id', v_current.id, 'reason', 'added'));
      elsif (v_seen->>v_current.id::text)::timestamptz
            is distinct from v_current.updated_at then
        v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
          'line_id', v_current.id, 'reason', 'changed'));
      end if;
    end loop;
  end if;

  select *
    into v_job
    from public.mechanic_jobs j
   where j.id = p_job_id
     and j.tenant_id = v_tenant_id
     and j.deleted_at is null
   for update;

  if not found then
    raise exception 'Trabajo no encontrado o eliminado.' using errcode = 'P0002';
  end if;

  if v_job.invoice_id is distinct from v_invoice_id then
    raise exception 'El vínculo financiero del trabajo cambió mientras se guardaba; vuelve a intentarlo.'
      using errcode = 'PT409', hint = 'retry';
  end if;

  -- Las bicis del trabajo después del trabajo: una línea escrita por su
  -- cuenta toma el trabajo en su guardia de pago y su bici después, en el
  -- disparador de costos (línea → trabajo → bici). Tomarlas antes que el
  -- trabajo cruzaba con eso (revisiones de Codex, 2026-09-28). Una que el
  -- formulario manda por id y ya no está, la quitó otro.
  if p_job_bikes is not null then
    for v_current in
      select jb.id
        from public.mechanic_job_bikes jb
       where jb.tenant_id = v_tenant_id
         and jb.job_id = p_job_id
       order by jb.id
       for update
    loop
      v_current_job_bike_ids := v_current_job_bike_ids || v_current.id;
    end loop;
    select jsonb_agg(jsonb_build_object(
             'job_bike_id', sent.id, 'reason', 'removed') order by sent.id)
      into v_job_bike_conflicts
      from unnest(v_job_bike_sent_ids) as sent(id)
     where not (sent.id = any (v_current_job_bike_ids));
    if v_job_bike_conflicts is not null then
      raise exception 'Otra persona quitó una bici de este trabajo mientras lo editabas; recárgalo antes de guardar.'
        using errcode = 'PT409',
              detail = v_job_bike_conflicts::text,
              hint = 'job_bikes_changed';
    end if;
    v_job_bike_conflicts := '[]'::jsonb;
  end if;

  -- La factura con pagos: el mismo predicado que las guardias de pago.
  v_invoice_lock := public.mechanic_job_invoice_lock_internal(
    v_tenant_id, v_invoice_id);
  v_invoice_paid := coalesce(v_invoice_lock = 'paid', false);

  -- La factura confirmada y sin pagos ya descontó stock y tiene su asiento, y
  -- desde el trabajo sólo se podría sincronizar saltando ese recálculo
  -- (`mechanic_job_invoice_step_internal`). Lo que cambiaría lo que se cobra
  -- se rechaza aquí, antes de escribir nada, igual que con pagos: las líneas
  -- (nuevas, cambiadas o quitadas), el descuento y lo protegido de la
  -- cabecera y de cada bici. El diagnóstico sigue. Se corrige desde la
  -- factura, que rehace stock y asiento y lo proyecta al trabajo. Antes el
  -- comando escribía las líneas y después dejaba la factura como estaba: el
  -- trabajo y su factura quedaban distintos (revisión del 2026-09-28).
  -- Una nota de crédito contabilizada también: la guardia de la factura
  -- (`prevent_sales_invoice_edit_with_credit`) rechazaría la sincronización
  -- y el trabajo quedaría cambiado con la factura de antes (cuarta revisión
  -- de Codex). Puede existir sobre una factura emitida, que el inventario
  -- aún no trata como confirmada.
  v_invoice_posted := coalesce(v_invoice_lock = 'posted', false);
  select invoice.invoice_number
    into v_invoice_number
    from public.sales_invoices invoice
   where invoice.id = v_invoice_id
     and invoice.tenant_id = v_tenant_id;

  if v_invoice_posted then
    select coalesce(jsonb_agg(key order by key), '[]'::jsonb)
      into v_posted_changes
      from jsonb_object_keys(v_header) as key
     where key = any (v_paid_protected_columns);

    if p_lines is not null then
      for v_line in select value from jsonb_array_elements(p_lines)
      loop
        v_row := jsonb_populate_record(
          null::public.mechanic_job_items,
          v_line - 'client_key' - 'job_bike_key'
        );
        -- Lo mismo que la escritura de abajo, para comparar lo mismo.
        v_row.product_name := btrim(v_row.product_name);
        v_row.quantity := coalesce(v_row.quantity, 1);
        v_row.unit_price := coalesce(v_row.unit_price, 0);
        v_row.item_type := coalesce(v_row.item_type, 'product');
        v_row.location_key := coalesce(v_row.location_key, 'none');
        v_row.creates_lifecycle := coalesce(v_row.creates_lifecycle, false);
        if v_row.id is null
           or v_line ? 'job_bike_key'
           or exists (
             select 1
               from public.mechanic_job_items i
              where i.id = v_row.id
                and i.tenant_id = v_tenant_id
                and i.job_id = p_job_id
                and (
                  i.job_bike_id, i.product_id, i.service_product_id,
                  i.product_name, i.product_sku, i.quantity, i.unit_price,
                  i.notes, i.service_configuration_data, i.item_type,
                  i.system_key, i.component_slot_key, i.location_key,
                  i.intervention_type, i.creates_lifecycle
                ) is distinct from (
                  v_row.job_bike_id, v_row.product_id, v_row.service_product_id,
                  v_row.product_name, v_row.product_sku, v_row.quantity,
                  v_row.unit_price, v_row.notes, v_row.service_configuration_data,
                  v_row.item_type, v_row.system_key, v_row.component_slot_key,
                  v_row.location_key, v_row.intervention_type,
                  v_row.creates_lifecycle
                )
           ) then
          v_posted_changes := v_posted_changes
            || jsonb_build_array('línea: ' || v_row.product_name);
        end if;
      end loop;
      select v_posted_changes || coalesce(jsonb_agg(
               'quitar: ' || i.product_name order by i.product_name), '[]'::jsonb)
        into v_posted_changes
        from public.mechanic_job_items i
       where i.tenant_id = v_tenant_id
         and i.job_id = p_job_id
         and i.id = any (v_current_ids)
         and not (i.id = any (v_kept_ids));
    end if;

    if p_job_bikes is not null then
      for v_job_bike in select value from jsonb_array_elements(p_job_bikes)
      loop
        if nullif(v_job_bike->>'id', '') is null then
          -- Una bici nueva cambia lo que se cobra sólo con sus líneas, que ya
          -- se cuentan arriba.
          continue;
        end if;
        select *
          into v_job_bike_old
          from public.mechanic_job_bikes jb
         where jb.id = (v_job_bike->>'id')::uuid
           and jb.tenant_id = v_tenant_id
           and jb.job_id = p_job_id;
        continue when not found or v_job_bike ? 'remove';
        v_job_bike_new := jsonb_populate_record(
          v_job_bike_old, v_job_bike - v_job_bike_meta);
        select v_posted_changes || coalesce(jsonb_agg(
                 'bici: ' || column_name order by column_name), '[]'::jsonb)
          into v_posted_changes
          from unnest(v_job_bike_paid_columns) as column_name
         where (to_jsonb(v_job_bike_new)->column_name)
               is distinct from (to_jsonb(v_job_bike_old)->column_name);
      end loop;
    end if;

    if jsonb_array_length(v_posted_changes) > 0 then
      raise exception 'La factura % de este trabajo ya está confirmada o tiene notas de crédito. Lo que se cobra (productos, precios, descuento, cliente, modalidad) se corrige desde la factura, que rehace stock y contabilidad; el diagnóstico sí puede seguir editándose.',
          coalesce(v_invoice_number, 'vinculada')
        using errcode = '55000',
              detail = v_posted_changes::text,
              hint = 'invoice_posted';
    end if;
  end if;

  -- Con la factura pagada, la cabecera acepta lo mismo que el formulario
  -- manda en ese caso: diagnóstico, notas, fechas, prioridad, horas y fotos.
  -- La guardia de pago de `mechanic_jobs` cubre cliente, modalidad y
  -- descuento, pero no la garantía, la aprobación ni la cotización; el
  -- formulario las quitaba y el comando las habría aceptado (revisión de
  -- Codex, 2026-09-28).
  select jsonb_agg(key order by key)
    into v_paid_fields
    from jsonb_object_keys(v_header) as key
   where key = any (v_paid_protected_columns);
  if v_paid_fields is not null and v_invoice_paid then
    raise exception 'La factura del trabajo ya tiene pagos. Cliente, modalidad, garantía, aprobación y descuento quedan protegidos; el diagnóstico sí puede seguir editándose.'
      using errcode = '55000',
            detail = v_paid_fields::text;
  end if;

  -- La cabecera: cada campo cambiado debe seguir como lo vio el formulario.
  -- Se compara ya con el tipo de la columna (una fecha o un número pueden
  -- llegar escritos distinto y ser lo mismo).
  if v_header <> '{}'::jsonb then
    v_header_expected := jsonb_populate_record(v_job, (
      select jsonb_object_agg(key, value->'expected') from jsonb_each(v_header)
    ));
    v_header_new := jsonb_populate_record(v_job, (
      select jsonb_object_agg(key, value->'value') from jsonb_each(v_header)
    ));
    for v_column in select jsonb_object_keys(v_header) order by 1
    loop
      if (to_jsonb(v_job)->v_column)
         is distinct from (to_jsonb(v_header_expected)->v_column) then
        v_header_conflicts := v_header_conflicts || jsonb_build_array(v_column);
      end if;
    end loop;
    if jsonb_array_length(v_header_conflicts) > 0 then
      raise exception 'Otra persona cambió la cabecera del trabajo mientras lo editabas; recárgalo antes de guardar.'
        using errcode = 'PT409',
              detail = v_header_conflicts::text,
              hint = 'job_header_changed';
    end if;

    -- Sólo las columnas cambiadas: los disparadores `UPDATE OF` de las demás
    -- no corren. El descuento va al final.
    select string_agg(format('%I = ($1).%I', key, key), ', ' order by key)
      into v_header_set
      from jsonb_object_keys(v_header) as key
     where key <> 'discount_amount';
    if v_header_set is not null then
      execute format(
        'update public.mechanic_jobs set %s where id = $2 and tenant_id = $3',
        v_header_set
      ) using v_header_new, p_job_id, v_tenant_id;
    end if;
  end if;

  -- Las bicis del trabajo, antes que las líneas que las nombran. Antes el
  -- formulario las escribía por su cuenta, antes de este comando, y un
  -- guardado rechazado dejaba el diagnóstico de la bici sin las líneas ni la
  -- cabecera (revisión de Codex, 2026-09-28). Primero se revisa todo: cada
  -- campo como se vio (si otro lo cambió, nada se guarda) y, con la factura
  -- pagada, que no cambien las marcas ni el orden, que la guardia de pago de
  -- la bici no compara.
  if p_job_bikes is not null then
    for v_job_bike in select value from jsonb_array_elements(p_job_bikes)
    loop
      continue when nullif(v_job_bike->>'id', '') is null;
      select *
        into v_job_bike_old
        from public.mechanic_job_bikes jb
       where jb.id = (v_job_bike->>'id')::uuid
         and jb.tenant_id = v_tenant_id
         and jb.job_id = p_job_id;
      -- La que sale y ya no está, la quitó otro: ya se fue.
      continue when not found;
      v_job_bike_expected := jsonb_populate_record(
        v_job_bike_old, v_job_bike->'expected');
      if v_job_bike ? 'remove' then
        for v_column in
          select key from jsonb_object_keys(v_job_bike->'expected') as key
           order by key
        loop
          if (to_jsonb(v_job_bike_old)->v_column)
             is distinct from (to_jsonb(v_job_bike_expected)->v_column) then
            v_job_bike_conflicts := v_job_bike_conflicts || jsonb_build_array(
              jsonb_build_object('job_bike_id', v_job_bike_old.id,
                                 'field', v_column));
          end if;
        end loop;
        continue;
      end if;
      v_job_bike_new := jsonb_populate_record(
        v_job_bike_old, v_job_bike - v_job_bike_meta);
      if (v_job_bike->>'bike_id')::uuid is distinct from v_job_bike_old.bike_id then
        raise exception 'Job bike % is another bicycle', v_job_bike_old.id
          using errcode = '22023';
      end if;
      for v_column in
        select key from jsonb_object_keys(v_job_bike - v_job_bike_meta) as key
         order by key
      loop
        if (to_jsonb(v_job_bike_old)->v_column)
           is distinct from (to_jsonb(v_job_bike_expected)->v_column) then
          v_job_bike_conflicts := v_job_bike_conflicts || jsonb_build_array(
            jsonb_build_object('job_bike_id', v_job_bike_old.id,
                               'field', v_column));
        end if;
        if v_invoice_paid
           and v_column = any (v_job_bike_paid_columns)
           and (to_jsonb(v_job_bike_new)->v_column)
               is distinct from (to_jsonb(v_job_bike_old)->v_column) then
          v_job_bike_paid := v_job_bike_paid || jsonb_build_array(v_column);
        end if;
      end loop;
    end loop;
    if jsonb_array_length(v_job_bike_conflicts) > 0 then
      raise exception 'Otra persona cambió una bici de este trabajo mientras lo editabas; recárgalo antes de guardar.'
        using errcode = 'PT409',
              detail = v_job_bike_conflicts::text,
              hint = 'job_bikes_changed';
    end if;
    if jsonb_array_length(v_job_bike_paid) > 0 then
      raise exception 'La factura del trabajo ya tiene pagos. El orden y las marcas de garantía y aprobación de cada bici quedan protegidos; el diagnóstico sí puede seguir editándose.'
        using errcode = '55000',
              detail = v_job_bike_paid::text;
    end if;

    for v_job_bike in select value from jsonb_array_elements(p_job_bikes)
    loop
      continue when v_job_bike ? 'remove';
      if nullif(v_job_bike->>'id', '') is not null then
        select *
          into v_job_bike_old
          from public.mechanic_job_bikes jb
         where jb.id = (v_job_bike->>'id')::uuid
           and jb.tenant_id = v_tenant_id
           and jb.job_id = p_job_id;
        v_job_bike_new := jsonb_populate_record(
          v_job_bike_old, v_job_bike - v_job_bike_meta);
        select string_agg(format('%I = ($1).%I', key, key), ', ' order by key)
          into v_job_bike_set
          from jsonb_object_keys(v_job_bike - v_job_bike_meta) as key
         where (to_jsonb(v_job_bike_new)->key)
               is distinct from (to_jsonb(v_job_bike_old)->key);
        if v_job_bike_set is not null then
          execute format(
            'update public.mechanic_job_bikes set %s, updated_at = clock_timestamp() '
            'where id = $2 and tenant_id = $3',
            v_job_bike_set
          ) using v_job_bike_new, v_job_bike_old.id, v_tenant_id;
          v_job_bikes_updated := v_job_bikes_updated + 1;
        end if;
        v_job_bike_id := v_job_bike_old.id;
      else
        v_job_bike_new := jsonb_populate_record(
          null::public.mechanic_job_bikes, v_job_bike - v_job_bike_meta);
        v_job_bike_new.bike_id := (v_job_bike->>'bike_id')::uuid;
        begin
          insert into public.mechanic_job_bikes (
            tenant_id, job_id, bike_id, order_index, diagnosis,
            work_requested, work_performed, technician_notes,
            diagnosis_sheet_key, diagnosis_sheet_data,
            diagnosis_sheet_updated_at, is_warranty_work, requires_approval,
            approved_by_customer
          ) values (
            v_tenant_id, p_job_id, v_job_bike_new.bike_id,
            coalesce(v_job_bike_new.order_index, 0), v_job_bike_new.diagnosis,
            v_job_bike_new.work_requested, v_job_bike_new.work_performed,
            v_job_bike_new.technician_notes, v_job_bike_new.diagnosis_sheet_key,
            coalesce(v_job_bike_new.diagnosis_sheet_data, '{}'::jsonb),
            v_job_bike_new.diagnosis_sheet_updated_at,
            coalesce(v_job_bike_new.is_warranty_work, false),
            coalesce(v_job_bike_new.requires_approval, false),
            coalesce(v_job_bike_new.approved_by_customer, false)
          )
          returning id into v_job_bike_id;
        exception when unique_violation then
          raise exception 'Otra persona agregó esa bici a este trabajo mientras lo editabas; recárgalo antes de guardar.'
            using errcode = 'PT409',
                  detail = jsonb_build_array(jsonb_build_object(
                    'bike_id', v_job_bike_new.bike_id,
                    'reason', 'added'))::text,
                  hint = 'job_bikes_changed';
        end;
        v_job_bikes_inserted := v_job_bikes_inserted + 1;
      end if;
      v_job_bike_keys := v_job_bike_keys || jsonb_build_object(
        v_job_bike->>'client_key', v_job_bike_id);
    end loop;
  end if;

  if p_lines is not null then
    -- Una línea que otro agregó mientras se tomaban las demás: su disparador
    -- de costos ya no puede tomar el trabajo, así que la que no esté aquí
    -- llega después de este guardado.
    for v_current in
      select i.id
        from public.mechanic_job_items i
       where i.tenant_id = v_tenant_id
         and i.job_id = p_job_id
         and not (i.id = any (v_current_ids))
    loop
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'line_id', v_current.id, 'reason', 'added'));
    end loop;

    for v_seen_id in select jsonb_object_keys(v_seen)
    loop
      if not (v_seen_id::uuid = any (v_current_ids)) then
        v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
          'line_id', v_seen_id::uuid, 'reason', 'removed'));
      end if;
    end loop;

    if jsonb_array_length(v_conflicts) > 0 then
      raise exception 'Las líneas del trabajo cambiaron mientras lo editabas; recárgalo antes de guardar.'
        using errcode = 'PT409',
              detail = v_conflicts::text,
              hint = 'job_lines_changed';
    end if;

    -- Cambiadas y nuevas primero, borradas al final.
    for v_line in select value from jsonb_array_elements(p_lines)
    loop
      if v_line ? 'job_bike_key' then
        v_line := (v_line - 'job_bike_key') || jsonb_build_object(
          'job_bike_id', v_job_bike_keys->(v_line->>'job_bike_key'));
      end if;
      v_row := jsonb_populate_record(
        null::public.mechanic_job_items,
        v_line - 'client_key'
      );
      v_row.product_name := btrim(v_row.product_name);
      v_row.quantity := coalesce(v_row.quantity, 1);
      v_row.unit_price := coalesce(v_row.unit_price, 0);
      v_row.item_type := coalesce(v_row.item_type, 'product');
      v_row.location_key := coalesce(v_row.location_key, 'none');
      v_row.creates_lifecycle := coalesce(v_row.creates_lifecycle, false);

      if v_row.job_bike_id is not null and not exists (
        select 1
          from public.mechanic_job_bikes jb
         where jb.id = v_row.job_bike_id
           and jb.job_id = p_job_id
           and jb.tenant_id = v_tenant_id
      ) then
        raise exception 'La línea «%» es de una bici que no está en este trabajo.', v_row.product_name
          using errcode = '23503';
      end if;
      -- Una bici que sale del trabajo se lleva sus líneas en cascada: una
      -- línea que la nombra no puede quedar.
      if v_row.job_bike_id = any (v_removed_job_bike_ids) then
        raise exception 'La línea «%» es de una bici que sale de este trabajo.', v_row.product_name
          using errcode = '22023';
      end if;

      if v_row.id is not null then
        update public.mechanic_job_items i
           set job_bike_id = v_row.job_bike_id,
               product_id = v_row.product_id,
               service_product_id = v_row.service_product_id,
               product_name = v_row.product_name,
               product_sku = v_row.product_sku,
               quantity = v_row.quantity,
               unit_price = v_row.unit_price,
               notes = v_row.notes,
               service_configuration_data = v_row.service_configuration_data,
               item_type = v_row.item_type,
               system_key = v_row.system_key,
               component_slot_key = v_row.component_slot_key,
               location_key = v_row.location_key,
               intervention_type = v_row.intervention_type,
               creates_lifecycle = v_row.creates_lifecycle
         where i.id = v_row.id
           and i.tenant_id = v_tenant_id
           and i.job_id = p_job_id
           and (
             i.job_bike_id, i.product_id, i.service_product_id, i.product_name,
             i.product_sku, i.quantity, i.unit_price, i.notes,
             i.service_configuration_data, i.item_type, i.system_key,
             i.component_slot_key, i.location_key, i.intervention_type,
             i.creates_lifecycle
           ) is distinct from (
             v_row.job_bike_id, v_row.product_id, v_row.service_product_id,
             v_row.product_name, v_row.product_sku, v_row.quantity,
             v_row.unit_price, v_row.notes, v_row.service_configuration_data,
             v_row.item_type, v_row.system_key, v_row.component_slot_key,
             v_row.location_key, v_row.intervention_type, v_row.creates_lifecycle
           );
        get diagnostics v_count = row_count;
        v_updated := v_updated + v_count;
        v_line_id := v_row.id;
      else
        insert into public.mechanic_job_items (
          tenant_id, job_id, job_bike_id, product_id, service_product_id,
          product_name, product_sku, quantity, unit_price, notes,
          service_configuration_data, item_type, system_key,
          component_slot_key, location_key, intervention_type,
          creates_lifecycle
        ) values (
          v_tenant_id, p_job_id, v_row.job_bike_id, v_row.product_id,
          v_row.service_product_id, v_row.product_name, v_row.product_sku,
          v_row.quantity, v_row.unit_price, v_row.notes,
          v_row.service_configuration_data, v_row.item_type, v_row.system_key,
          v_row.component_slot_key, v_row.location_key, v_row.intervention_type,
          v_row.creates_lifecycle
        )
        returning id into v_line_id;
        v_inserted := v_inserted + 1;

        -- Las tareas las acaba de crear su disparador; el recibo las cuenta.
        v_tasks_created := v_tasks_created + (
          select count(*)::integer
            from public.mechanic_job_tasks task
           where task.tenant_id = v_tenant_id
             and task.parent_item_id = v_line_id);
      end if;
      v_line_keys := v_line_keys || jsonb_build_object(
        v_line_id::text, v_line->>'client_key');
    end loop;

    delete from public.mechanic_job_items i
     where i.tenant_id = v_tenant_id
       and i.job_id = p_job_id
       and i.id = any (v_current_ids)
       and not (i.id = any (v_kept_ids));
    get diagnostics v_deleted = row_count;

    -- Las bicis que el formulario quitó, al final como antes. Una que ya no
    -- estaba, la quitó otro: ya se fue.
    if cardinality(v_removed_job_bike_ids) > 0 then
      delete from public.mechanic_job_bikes jb
       where jb.tenant_id = v_tenant_id
         and jb.job_id = p_job_id
         and jb.id = any (v_removed_job_bike_ids);
      get diagnostics v_job_bikes_deleted = row_count;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
             'id', i.id,
             'client_key', v_line_keys->>(i.id::text),
             'updated_at', i.updated_at
           ) order by i.created_at, i.id), '[]'::jsonb)
      into v_lines_result
      from public.mechanic_job_items i
     where i.tenant_id = v_tenant_id
       and i.job_id = p_job_id;
  end if;

  -- El descuento, con el subtotal de las líneas ya nuevas, y el total que lo
  -- descuenta: el recálculo sólo corre cuando cambia una línea, y antes el
  -- descuento llegaba en la fila completa, antes que ellas.
  if v_header ? 'discount_amount' then
    update public.mechanic_jobs
       set discount_amount = v_header_new.discount_amount
     where id = p_job_id
       and tenant_id = v_tenant_id;
    perform public.recalculate_mechanic_job_costs(p_job_id);
  end if;

  -- Lo que confirmó «Configurar», en la misma transacción que sus líneas.
  for v_entry in select value from jsonb_array_elements(p_bike_facts)
  loop
    v_bike_id := (v_entry->>'bike_id')::uuid;
    begin
      v_fact_result := public.patch_bike_technical_facts_v1(
        v_operation_key || ':ficha:' || v_bike_id::text,
        v_bike_id,
        p_job_id,
        'service_wizard',
        v_entry->'facts'
      );
    exception when others then
      get stacked diagnostics
        v_state = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail;
      -- Sólo lo que dice la ficha lleva la pista: que cambió (PT409) o que no
      -- acepta el dato (clases 22, 23, 42 y P0). Un error pasajero (un
      -- deadlock, un corte) sale igual que llegó y no descarta lo pendiente
      -- (revisión de Codex, 2026-09-28).
      if v_state = 'PT409' or left(v_state, 2) in ('22', '23', '42', 'P0') then
        raise exception using
          errcode = v_state,
          message = v_message,
          detail = coalesce(v_detail, ''),
          hint = 'bike_facts:' || v_bike_id::text;
      end if;
      raise;
    end;
    v_fact_results := v_fact_results || jsonb_build_array(jsonb_build_object(
      'bike_id', v_bike_id,
      'result', v_fact_result
    ));
  end loop;

  -- La factura del trabajo al día, en la misma transacción que el recibo
  -- (`p_invoice`): lo que el botón Guardar hacía después, con su propia
  -- llamada, no estaba en la bandeja, y un comando confirmado tras cerrar la
  -- app o perder la respuesta dejaba el trabajo sin factura, o con la
  -- factura de las líneas y el descuento de antes (revisiones de Codex,
  -- 2026-09-28). La decisión vive en `mechanic_job_invoice_step_internal`:
  -- un error pasajero deshace el guardado entero (`55P03`, la bandeja lo
  -- reintenta), uno del dato lo deja guardado con `failed` en el recibo.
  if coalesce(p_invoice, false) then
    v_invoice_result := public.mechanic_job_invoice_step_internal(
      v_tenant_id, p_job_id);
  end if;

  -- La cabecera como quedó, con lo que hayan ajustado sus disparadores.
  select jsonb_object_agg(field.key, field.value)
    into v_header_result
    from public.mechanic_jobs j,
         jsonb_each(to_jsonb(j)) as field
   where j.id = p_job_id
     and j.tenant_id = v_tenant_id
     and field.key = any (v_header_columns);

  if p_job_bikes is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', jb.id,
             'client_key', keys.key,
             'bike_id', jb.bike_id,
             'row', (select jsonb_object_agg(field.key, field.value)
                       from jsonb_each(to_jsonb(jb)) as field
                      where field.key = any (v_job_bike_columns))
           ) order by jb.order_index, jb.id), '[]'::jsonb)
      into v_job_bikes_result
      from public.mechanic_job_bikes jb
      left join jsonb_each_text(v_job_bike_keys) as keys
        on keys.value = jb.id::text
     where jb.tenant_id = v_tenant_id
       and jb.job_id = p_job_id;
  end if;

  v_result := jsonb_build_object(
    'operation_id', v_operation_id,
    'job_id', p_job_id,
    'header', v_header_result,
    'job_bikes', v_job_bikes_result,
    'invoice', v_invoice_result,
    'job_bikes_inserted', v_job_bikes_inserted,
    'job_bikes_updated', v_job_bikes_updated,
    'job_bikes_deleted', v_job_bikes_deleted,
    'lines', v_lines_result,
    'inserted', v_inserted,
    'tasks_created', v_tasks_created,
    'updated', v_updated,
    'deleted', v_deleted,
    'bike_facts', v_fact_results,
    'replayed', false
  );

  insert into public.mechanic_job_line_saves (
    id, tenant_id, operation_key, payload_hash, job_id, result_snapshot,
    created_by
  ) values (
    v_operation_id, v_tenant_id, v_operation_key, v_payload_hash, p_job_id,
    v_result, v_actor_id
  );

  return v_result;
end;
$function$;

-- El recibo, sin escribir nada: la bandeja del equipo pregunta por la llave
-- después de un corte o de una respuesta perdida, antes de decidir si
-- reenviar. Sólo ve los recibos de su propio taller.
create or replace function public.get_mechanic_job_line_save_v1(
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_active_profile_count integer;
  v_tenant_id uuid;
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

  if not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select receipt.result_snapshot || jsonb_build_object('replayed', true)
    into v_result
    from public.mechanic_job_line_saves receipt
   where receipt.tenant_id = v_tenant_id
     and receipt.operation_key = nullif(btrim(p_operation_key), '');

  return v_result;
end;
$function$;

revoke all on function public.get_mechanic_job_line_save_v1(text)
  from public, anon, service_role;

grant execute on function public.get_mechanic_job_line_save_v1(text)
  to authenticated;

-- La continuación de la factura de un guardado ya escrito. Cuando el recibo
-- de la llave dice `failed`, la bandeja del equipo guarda esta continuación
-- y la llama sin otro Guardar: al abrir la sesión, al volver al frente, cada
-- tanto con espera creciente y al abrir el trabajo. Sólo necesita la llave
-- (no el pedido entero), así que es la misma para cualquier guardado del
-- trabajo. Repetirla no hace dos facturas: con una ya vinculada, crear
-- devuelve ésa y sincronizar deja lo mismo. Si el recibo ya no dice `failed`
-- (otra continuación, o la repetición del guardado, la hizo), devuelve lo
-- que dice sin escribir. Toma la misma llave que el guardado, y después
-- factura → trabajo, como él.
create or replace function public.continue_mechanic_job_invoice_v1(
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_active_profile_count integer;
  v_tenant_id uuid;
  v_operation_key text := nullif(btrim(p_operation_key), '');
  v_receipt public.mechanic_job_line_saves%rowtype;
  v_invoice jsonb;
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

  if not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  if v_operation_key is null or length(v_operation_key) > 80 then
    raise exception 'A valid job line save operation key is required'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant_id::text || ':job_line_save:' || v_operation_key, 0)
  );

  select *
    into v_receipt
    from public.mechanic_job_line_saves receipt
   where receipt.tenant_id = v_tenant_id
     and receipt.operation_key = v_operation_key;

  if not found then
    raise exception 'No hay un guardado del trabajo con esa llave en este taller.'
      using errcode = 'P0002';
  end if;

  if coalesce(v_receipt.result_snapshot->'invoice'->>'action', '') <> 'failed' then
    return jsonb_build_object(
      'operation_id', v_receipt.id,
      'job_id', v_receipt.job_id,
      'invoice', v_receipt.result_snapshot->'invoice',
      'replayed', true
    );
  end if;

  if v_receipt.job_id is null then
    -- El trabajo se borró: ya no hay factura que hacer.
    v_invoice := jsonb_build_object('action', 'none', 'invoice_id', null, 'error', null);
  else
    v_invoice := public.mechanic_job_invoice_step_internal(
      v_tenant_id, v_receipt.job_id);
  end if;

  update public.mechanic_job_line_saves
     set result_snapshot = jsonb_set(result_snapshot, '{invoice}', v_invoice)
   where id = v_receipt.id;

  return jsonb_build_object(
    'operation_id', v_receipt.id,
    'job_id', v_receipt.job_id,
    'invoice', v_invoice,
    'replayed', false
  );
end;
$function$;

revoke all on function public.continue_mechanic_job_invoice_v1(text)
  from public, anon, service_role;

grant execute on function public.continue_mechanic_job_invoice_v1(text)
  to authenticated;

revoke all on function public.save_mechanic_job_lines_v1(
  text, uuid, jsonb, jsonb, jsonb, jsonb, jsonb, boolean
) from public, anon, service_role;

grant execute on function public.save_mechanic_job_lines_v1(
  text, uuid, jsonb, jsonb, jsonb, jsonb, jsonb, boolean
) to authenticated;


-- ============================================================================
-- Las escrituras directas y `sync_job_to_invoice` tampoco cambian una factura
-- confirmada (revisión de Codex del 2026-09-28)
-- ============================================================================
-- La guardia del comando no bastaba: la pestaña Tareas inserta líneas por su
-- cuenta y un Guardar sin cambios llama a `sync_job_to_invoice`, que
-- reescribía una factura confirmada sin pagos con la marca que salta stock y
-- asiento. Las dos guardias de escritura directa y la sincronización usan
-- ahora la misma regla que el comando (`mechanic_job_invoice_lock_internal`).
-- La proyección desde la factura (`app.syncing_invoice_to_job`) sigue
-- pasando: es la corrección auditada. Se editan sobre la definición vigente
-- (idéntica en local y producción el 2026-09-28).

CREATE OR REPLACE FUNCTION public.guard_paid_workshop_job_commercial_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '750ms'
AS $function$
begin
  if current_setting('app.syncing_invoice_to_job', true) = 'true'
     or old.invoice_id is null then
    return new;
  end if;

  if current_setting(
       'app.mechanic_job_sale_classification_rpc', true
     ) = 'true'
     and old.job_type = 'service'
     and old.workflow_kind = 'service'
     and old.intake_kind = 'unspecified'
     and old.mode_needs_review
     and old.bike_id is null
     and old.subject_id is null
     and new.job_type = 'service'
     and new.workflow_kind = 'sale'
     and new.intake_kind = 'none'
     and not new.mode_needs_review
     and new.mode_review_reason is null
     and new.bike_id is null
     and new.subject_id is null
     and row(
       old.tenant_id, old.customer_id, old.service_package_id,
       old.subject_notes, old.discount_amount, old.invoice_id
     ) is not distinct from row(
       new.tenant_id, new.customer_id, new.service_package_id,
       new.subject_notes, new.discount_amount, new.invoice_id
     )
     and not exists (
       select 1
       from public.mechanic_job_bikes job_bike
       where job_bike.tenant_id = old.tenant_id
         and job_bike.job_id = old.id
     ) then
    return new;
  end if;

  if row(
    old.customer_id, old.bike_id, old.service_package_id,
    old.job_type, old.workflow_kind, old.intake_kind,
    old.mode_needs_review, old.mode_review_reason,
    old.subject_id, old.subject_notes, old.discount_amount
  ) is not distinct from row(
    new.customer_id, new.bike_id, new.service_package_id,
    new.job_type, new.workflow_kind, new.intake_kind,
    new.mode_needs_review, new.mode_review_reason,
    new.subject_id, new.subject_notes, new.discount_amount
  ) then
    return new;
  end if;

  case public.mechanic_job_invoice_lock_internal(old.tenant_id, old.invoice_id)
    when 'paid' then
      raise exception 'La factura del trabajo ya tiene pagos. Cliente, modalidad, objeto recibido y descuento quedan protegidos.'
        using errcode = '55000';
    when 'posted' then
      raise exception 'La factura del trabajo ya está confirmada o tiene notas de crédito. Cliente, modalidad, objeto recibido y descuento se corrigen desde la factura.'
        using errcode = '55000', hint = 'invoice_posted';
    else
      null;
  end case;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.guard_paid_workshop_child_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '750ms'
AS $function$
declare
  v_changed boolean := true;
  v_job public.mechanic_jobs%rowtype;
  v_candidate record;
  v_old_job_id uuid;
  v_new_job_id uuid;
begin
  if current_setting('app.syncing_invoice_to_job', true) = 'true' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if tg_table_name = 'mechanic_job_items' then
      v_changed := (to_jsonb(old) - 'updated_at' - 'created_at')
        is distinct from
        (to_jsonb(new) - 'updated_at' - 'created_at');
    else
      v_changed := row(
        old.tenant_id, old.job_id, old.bike_id,
        old.parts_cost, old.labor_cost, old.subtotal
      ) is distinct from row(
        new.tenant_id, new.job_id, new.bike_id,
        new.parts_cost, new.labor_cost, new.subtotal
      );
    end if;
    if not v_changed then return new; end if;
  end if;

  if tg_op <> 'INSERT' then v_old_job_id := old.job_id; end if;
  if tg_op <> 'DELETE' then v_new_job_id := new.job_id; end if;

  for v_candidate in
    select distinct candidate.job_id
    from unnest(array[
      v_old_job_id,
      v_new_job_id
    ]::uuid[]) candidate(job_id)
    where candidate.job_id is not null
    order by candidate.job_id
  loop
    select job.* into v_job
    from public.mechanic_jobs job
    where job.id = v_candidate.job_id
    for update;
    if not found or v_job.invoice_id is null then continue; end if;

    case public.mechanic_job_invoice_lock_internal(v_job.tenant_id, v_job.invoice_id)
      when 'paid' then
        raise exception 'La factura del trabajo ya tiene pagos. Productos, precios y bicicleta recibida quedan protegidos; el diagnóstico sí puede seguir editándose.'
          using errcode = '55000';
      when 'posted' then
        raise exception 'La factura del trabajo ya está confirmada o tiene notas de crédito. Productos, precios y bicicleta recibida se corrigen desde la factura, que rehace stock y contabilidad; el diagnóstico sí puede seguir editándose.'
          using errcode = '55000', hint = 'invoice_posted';
      else
        null;
    end case;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sync_job_to_invoice(p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '750ms'
AS $function$
declare
  v_preflight_tenant_id uuid;
  v_preflight_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_existing jsonb;
  v_parts numeric(12,2) := 0;
  v_labor numeric(12,2) := 0;
  v_gross numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_has_financial_history boolean := false;
begin
  if p_job_id is null then return; end if;
  if current_setting('app.syncing_invoice_to_job', true) = 'true' then return; end if;

  select job.tenant_id, job.invoice_id
    into v_preflight_tenant_id, v_preflight_invoice_id
  from public.mechanic_jobs job
  where job.id = p_job_id;
  if not found or v_preflight_invoice_id is null then return; end if;
  perform public.assert_workshop_rpc_tenant(v_preflight_tenant_id);

  select invoice.* into v_invoice
  from public.sales_invoices invoice
  where invoice.id = v_preflight_invoice_id
    and invoice.tenant_id = v_preflight_tenant_id
  for update;
  if not found then
    raise exception 'La factura vinculada al trabajo no existe en el mismo tenant.';
  end if;

  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
  for update;
  if not found then
    raise exception 'El trabajo vinculado a la factura ya no existe.'
      using errcode = '40001';
  end if;
  if v_job.tenant_id is distinct from v_preflight_tenant_id
     or v_job.invoice_id is distinct from v_preflight_invoice_id then
    raise exception 'El vínculo financiero del trabajo cambió durante la sincronización; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  -- Confirmada o con nota de crédito, también (2026-09-28): la reescritura de
  -- abajo lleva la marca que hace saltar el recálculo de stock y asiento, y
  -- dejaría el total nuevo con el asiento de antes. Se corrige desde la
  -- factura.
  v_has_financial_history := public.mechanic_job_invoice_lock_internal(
    v_invoice.tenant_id, v_invoice.id) is not null;
  if v_has_financial_history then
    -- Never use an ordinary form save as a retroactive cleanup for historical
    -- paid rows. Production contains legitimate legacy differences, including
    -- richer workshop-only technical metadata. Payment-time guards prevent
    -- new drift; once financial history exists this command is an exact
    -- commercial no-op on both sides.
    return;
  end if;

  for v_item in
    select item.*,
           coalesce(nullif(concat_ws(' ', bike.brand, bike.model), ''), 'Bicicleta') as bike_name,
           product.cost as catalog_cost
      from public.mechanic_job_items item
      left join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
      left join public.bikes bike on bike.id = job_bike.bike_id
      left join public.products product
        on product.id = coalesce(item.product_id, item.service_product_id)
       and product.tenant_id = item.tenant_id
     where item.job_id = p_job_id
       and item.tenant_id = v_job.tenant_id
     order by item.created_at, item.id
  loop
    select element.value into v_existing
      from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb)) element(value)
     where element.value->>'id' = v_item.id::text
     limit 1;

    v_items := v_items || jsonb_build_object(
      'id', v_item.id,
      'product_id', case
        when v_item.item_type = 'service' then coalesce(v_item.service_product_id::text, '')
        when v_item.item_type = 'product' then coalesce(v_item.product_id::text, '')
        else ''
      end,
      'product_name', v_item.product_name,
      'product_sku', coalesce(v_item.product_sku, ''),
      'description', coalesce(v_item.notes, v_item.description, ''),
      'item_type', v_item.item_type,
      'is_service', v_item.item_type = 'service',
      'is_catalog_product',
        v_item.item_type <> 'adhoc'
        and coalesce(v_item.product_id, v_item.service_product_id) is not null,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'discount', coalesce(nullif(v_existing->>'discount', '')::numeric, 0),
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'cost', coalesce(nullif(v_existing->>'cost', '')::numeric, v_item.catalog_cost, 0),
      'purchase_treatment', coalesce(v_existing->>'purchase_treatment', 'inventory'),
      'job_bike_id', v_item.job_bike_id,
      'bike_name', case when v_item.job_bike_id is null then null else v_item.bike_name end,
      'service_configuration_data', v_item.service_configuration_data,
      'system_key', v_item.system_key,
      'component_slot_key', v_item.component_slot_key,
      'location_key', v_item.location_key,
      'intervention_type', v_item.intervention_type,
      'creates_lifecycle', v_item.creates_lifecycle
    );

    if v_item.item_type = 'product' then
      v_parts := v_parts + coalesce(v_item.total_price, 0);
    else
      v_labor := v_labor + coalesce(v_item.total_price, 0);
    end if;
  end loop;

  v_gross := round(v_parts + v_labor, 2);
  v_discount := round(coalesce(v_job.discount_amount, 0), 2);
  if v_discount < 0 or v_discount > v_gross then
    raise exception 'El descuento del trabajo debe estar entre cero y el subtotal (%).', v_gross;
  end if;
  v_total := v_gross - v_discount;

  -- Prevent the invoice UPDATE trigger from projecting the same payload back
  -- into child rows while this invoice -> job lock order is held. Besides
  -- avoiding redundant work, this is what keeps a concurrent child-row guard
  -- from forming an invoice/job/item wait cycle.
  perform set_config('app.syncing_job_to_invoice', 'true', true);
  update public.sales_invoices
     set items = v_items,
         subtotal = v_total,
         total = v_total,
         discount_amount = v_discount,
         updated_at = clock_timestamp()
   where id = v_invoice.id;

  perform public.recalculate_sales_invoice_payments(v_invoice.id);
  perform set_config('app.syncing_job_to_invoice', '', true);
exception
  when others then
    perform set_config('app.syncing_invoice_to_job', '', true);
    perform set_config('app.syncing_job_to_invoice', '', true);
    raise;
end;
$function$;

commit;
