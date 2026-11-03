-- Ajustes de cotizaciones en el ERP. El comando existía desde la fundación
-- (20261102041700) sin pantalla y con dos huecos: lo corría cualquiera del
-- equipo —la caja o un mecánico cambiaban la vigencia que se le promete al
-- cliente— y aceptaba un pago adelantado menor al 100 %, que aceptar una
-- oferta rechaza (`quote_deposit_unsupported`): con 50 %, ninguna oferta con
-- algo a pedido se podía aceptar.
--
-- Ahora cambia los valores quien cambia los ajustes del taller
-- (can_edit_tenant_settings: administración o el permiso edit_settings),
-- cada valor se valida con su nombre para que la pantalla diga cuál, el
-- recordatorio tiene que caer antes de que la oferta venza y el pago
-- adelantado queda en 100 % mientras no exista un abono.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- Lo que la pantalla muestra, y si quien mira puede cambiarlo.
create or replace function public.customer_quote_settings_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings public.customer_quote_settings;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  v_settings := public.customer_quote_settings_internal(p_tenant_id);
  return jsonb_build_object(
    'offer_validity_hours', v_settings.offer_validity_hours,
    'reminder_hours_before', v_settings.reminder_hours_before,
    'on_order_prepay_percent', v_settings.on_order_prepay_percent,
    'supplier_task_due_hours', v_settings.supplier_task_due_hours,
    'supplier_check_fresh_hours', v_settings.supplier_check_fresh_hours,
    'updated_at', v_settings.updated_at,
    'can_edit', public.can_edit_tenant_settings(p_tenant_id)
  );
end;
$$;

revoke all on function public.customer_quote_settings_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_settings_v1(uuid) to authenticated;

comment on function public.customer_quote_settings_v1(uuid) is
  'Los valores de las cotizaciones del taller (sin fila, los de omisión) y can_edit: si quien pregunta puede cambiarlos.';

-- Un valor entero entre [p_min] y [p_max], o el de ahora si no viene. El
-- nombre del campo va en el detalle para que la pantalla diga cuál.
create or replace function public.customer_quote_setting_value_internal(
  p_settings jsonb,
  p_key text,
  p_current integer,
  p_min integer,
  p_max integer
)
returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_raw jsonb := p_settings -> p_key;
  v_value numeric;
begin
  if v_raw is null or v_raw = 'null'::jsonb then
    return p_current;
  end if;
  if jsonb_typeof(v_raw) <> 'number' then
    raise exception 'quote_settings_invalid' using errcode = '22023', detail = p_key;
  end if;
  v_value := (v_raw #>> '{}')::numeric;
  if v_value <> trunc(v_value) or v_value < p_min or v_value > p_max then
    raise exception 'quote_settings_invalid' using errcode = '22023', detail = p_key;
  end if;
  return v_value::integer;
end;
$$;

revoke all on function public.customer_quote_setting_value_internal(jsonb, text, integer, integer, integer)
  from public, anon, authenticated, service_role;

create or replace function public.update_customer_quote_settings_v1(
  p_tenant_id uuid,
  p_settings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_current public.customer_quote_settings := public.customer_quote_settings_internal(p_tenant_id);
  v_validity integer;
  v_reminder integer;
  v_task_due integer;
  v_fresh integer;
begin
  if not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'quote_settings_not_allowed' using errcode = '42501';
  end if;
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'quote_settings_invalid' using errcode = '22023', detail = 'settings';
  end if;

  if p_settings ? 'on_order_prepay_percent'
     and p_settings -> 'on_order_prepay_percent' is distinct from '100'::jsonb then
    raise exception 'quote_deposit_unsupported' using errcode = '22023',
      detail = 'on_order_prepay_percent';
  end if;

  v_validity := public.customer_quote_setting_value_internal(
    p_settings, 'offer_validity_hours', v_current.offer_validity_hours, 12, 720);
  v_reminder := public.customer_quote_setting_value_internal(
    p_settings, 'reminder_hours_before', v_current.reminder_hours_before, 0, 168);
  v_task_due := public.customer_quote_setting_value_internal(
    p_settings, 'supplier_task_due_hours', v_current.supplier_task_due_hours, 1, 168);
  v_fresh := public.customer_quote_setting_value_internal(
    p_settings, 'supplier_check_fresh_hours', v_current.supplier_check_fresh_hours, 1, 720);

  -- Un recordatorio igual o mayor a la vigencia saldría junto con la oferta.
  if v_reminder >= v_validity then
    raise exception 'quote_settings_invalid' using errcode = '22023',
      detail = 'reminder_hours_before';
  end if;

  insert into public.customer_quote_settings (
    tenant_id, offer_validity_hours, reminder_hours_before, on_order_prepay_percent,
    supplier_task_due_hours, supplier_check_fresh_hours, notify_email, updated_by
  ) values (
    p_tenant_id, v_validity, v_reminder, 100, v_task_due, v_fresh,
    v_current.notify_email, v_actor
  )
  on conflict (tenant_id) do update
     set offer_validity_hours = excluded.offer_validity_hours,
         reminder_hours_before = excluded.reminder_hours_before,
         on_order_prepay_percent = excluded.on_order_prepay_percent,
         supplier_task_due_hours = excluded.supplier_task_due_hours,
         supplier_check_fresh_hours = excluded.supplier_check_fresh_hours,
         updated_at = clock_timestamp(),
         updated_by = v_actor;

  return public.customer_quote_settings_v1(p_tenant_id);
end;
$$;

revoke all on function public.update_customer_quote_settings_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.update_customer_quote_settings_v1(uuid, jsonb) to authenticated;

comment on function public.update_customer_quote_settings_v1(uuid, jsonb) is
  'Cambia los valores de las cotizaciones (vigencia, recordatorio, plazo de la tarea de proveedor y frescura de una revisión de portal). Sólo quien cambia los ajustes del taller; el pago adelantado queda en 100 % (quote_deposit_unsupported); quote_settings_invalid nombra el campo en el detalle.';

commit;
