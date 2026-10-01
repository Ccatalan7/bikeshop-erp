-- Deployment status: NOT DEPLOYED
-- Una línea corregida en un trabajo terminado escribe la ficha en la misma
-- transacción que la guarda (BIKE_WORKSHOP_MASTER_SCHEMA.md, ítem 4).
--
-- Hasta aquí la app guardaba la línea (un `update` de PostgREST) y después
-- llamaba `sync_job_installed_bike_facts_v1`. Si la app se cerraba entre las
-- dos, la línea decía 32H y la ficha seguía en 28H hasta la próxima vez que
-- alguien guardara el trabajo o cambiara su estado.
--
-- Ahora, con el trabajo FINALIZADO o ENTREGADO:
--
-- * Agregar una línea con perforaciones o cambiarle la configuración, la
--   ubicación o la bici aplica lo instalado del trabajo en la misma sentencia,
--   con la regla y la puerta de `20260928060000`
--   (`apply_job_installed_bike_facts_internal` →
--   `patch_bike_technical_facts_v1`). Si lo que esa línea instala no entra a
--   la ficha (sin empleado en la sesión, la bici tomada, un rechazo) o la
--   línea no se puede instalar (sin rueda, sin bici en un trabajo de varias,
--   un número imposible), el guardado de la línea falla con el motivo: línea
--   y ficha no quedan distintas por una edición (revisión del dueño,
--   2026-09-28: la primera versión guardaba la línea y se callaba).
-- * Borrar una línea, o quitarle las perforaciones, no se impide —la ficha
--   puede estar bien—, pero lo que esa línea escribió y ya no respalda queda
--   anotado en la historia de la bici en la misma transacción, sin esperar a
--   que la app llame después. Si ese aviso no se puede anotar (la historia
--   no lo acepta, la bici tomada), el borrado o el guardado falla: la línea
--   no se va sin su aviso (revisión del dueño, 2026-09-28).
--
-- La app sigue llamando `sync_job_installed_bike_facts_v1` después de
-- guardar: reintenta lo pendiente de otras líneas y devuelve los avisos.
--
-- Locks: línea (la fila que se escribe) → trabajo `for no key update` (el
-- mismo nivel que ya toma `update_mechanic_job_costs` en esa transacción) →
-- bici → ficha → llave de la operación. La transición toma trabajo → bici →
-- ficha y no toca líneas; ningún disparador del trabajo actualiza líneas.
--
-- Depende de `20260928060000`.
begin;

create or replace function public.apply_installed_bike_facts_on_job_line_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_line public.mechanic_job_items%rowtype;
  v_installs boolean := false;
  v_installed_before boolean := false;
  v_status text;
  v_result jsonb;
  v_problem jsonb;
  v_line_name text;
  v_fact text;
begin
  if tg_op = 'DELETE' then
    v_line := old;
    v_installed_before := old.service_configuration_data ? 'hole_count';
  else
    v_line := new;
    v_installs := new.service_configuration_data ? 'hole_count';
    if tg_op = 'UPDATE' then
      v_installed_before := old.service_configuration_data ? 'hole_count';
    end if;
  end if;
  if not v_installs and not v_installed_before then
    return null;
  end if;

  select j.status
    into v_status
    from public.mechanic_jobs j
   where j.id = v_line.job_id
     and j.tenant_id = v_line.tenant_id
     and j.deleted_at is null
   for no key update;

  if v_status is null or v_status not in ('FINALIZADO', 'ENTREGADO') then
    return null;
  end if;

  -- Los avisos que anota este cambio son obligatorios: si la historia de la
  -- bici no los acepta, la línea no se borra ni se guarda.
  v_result := public.apply_job_installed_bike_facts_internal(
    v_line.tenant_id,
    v_line.job_id,
    true
  );

  if not v_installs then
    return null;
  end if;

  -- Lo que esta línea instala tiene que quedar en la ficha con ella.
  select problem
    into v_problem
    from jsonb_array_elements(coalesce(v_result->'problems', '[]'::jsonb)) problem
   where problem->>'item_id' = v_line.id::text
     and problem->>'reason' in (
       'rejected', 'out_of_range', 'no_wheel', 'invalid_value', 'line_without_bike'
     )
   limit 1;
  if v_problem is null then
    return null;
  end if;

  v_line_name := coalesce(nullif(btrim(v_line.product_name), ''), 'La línea');
  v_fact := case
    when v_problem ? 'key'
      then public.installed_bike_fact_label(v_problem->>'key', v_problem->'value')
    else coalesce(v_problem->>'value', '?') || ' perforaciones'
  end;
  raise exception '%', case v_problem->>'reason'
      when 'rejected' then format(
        '«%s» no se guardó: la ficha de la bici no tomó %s (%s). En un '
        'trabajo terminado la línea y la ficha se guardan juntas; vuelve a '
        'intentarlo.', v_line_name, v_fact, v_problem->>'message')
      when 'out_of_range' then format(
        '«%s» no se guardó: %s está fuera de 12 a 48 perforaciones.',
        v_line_name, v_fact)
      when 'no_wheel' then format(
        '«%s» no se guardó: tiene perforaciones pero no dice qué rueda armó.',
        v_line_name)
      when 'invalid_value' then format(
        '«%s» no se guardó: %s no es un número de perforaciones.',
        v_line_name, coalesce(v_problem->>'value', '?'))
      else format(
        '«%s» no se guardó: no dice de qué bici del trabajo es.', v_line_name)
    end
    using errcode = '23514',
          detail = v_problem::text;
end;
$function$;

revoke all on function public.apply_installed_bike_facts_on_job_line_change()
  from public, anon, authenticated, service_role;

-- La app manda la fila completa en cada guardado: sólo cuenta lo que cambió
-- de verdad, no cada `update` que nombra la columna.
drop trigger if exists trg_mechanic_job_items_installed_bike_facts
  on public.mechanic_job_items;
drop trigger if exists trg_mechanic_job_items_installed_bike_facts_insert
  on public.mechanic_job_items;
drop trigger if exists trg_mechanic_job_items_installed_bike_facts_update
  on public.mechanic_job_items;
drop trigger if exists trg_mechanic_job_items_installed_bike_facts_delete
  on public.mechanic_job_items;
create trigger trg_mechanic_job_items_installed_bike_facts_insert
  after insert on public.mechanic_job_items
  for each row
  execute function public.apply_installed_bike_facts_on_job_line_change();
create trigger trg_mechanic_job_items_installed_bike_facts_update
  after update of service_configuration_data, location_key, job_bike_id
  on public.mechanic_job_items
  for each row
  when (
    old.service_configuration_data is distinct from new.service_configuration_data
    or old.location_key is distinct from new.location_key
    or old.job_bike_id is distinct from new.job_bike_id
  )
  execute function public.apply_installed_bike_facts_on_job_line_change();
create trigger trg_mechanic_job_items_installed_bike_facts_delete
  after delete on public.mechanic_job_items
  for each row
  execute function public.apply_installed_bike_facts_on_job_line_change();

commit;
