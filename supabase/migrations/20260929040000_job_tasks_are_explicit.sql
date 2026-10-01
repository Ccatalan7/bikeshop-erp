-- Las tareas de un trabajo las crea una persona; la descripción del catálogo
-- es instrucción (cierre del Master Schema, 2026-09-29).
--
-- Hasta hoy, cada línea nueva de un trabajo con un producto o servicio del
-- catálogo creaba tareas desde su descripción: el disparador
-- `trg_auto_parse_item_description` (renglones con viñeta o `1.`) y, en el
-- cliente publicado, `generateAutoTasksFromDescription` (cada renglón, con su
-- viñeta). Lo que se vio con los datos reales (producción, 2026-09-29, sólo
-- lectura):
-- - 370 tareas automáticas en 63 trabajos (46 entregados) y **ninguna marcada
--   hecha**; ninguna tarea manual ni cobrable en toda la base;
-- - 34 grupos repetidos en una misma línea («Cadena» junto a «-Cadena»);
-- - las 20 descripciones de servicios se muestran tal cual en la tienda
--   (`show_on_website`, sin descripción web aparte): son lo que el cliente
--   lee como «qué incluye», no una lista de trabajo;
-- - en ellas la viñeta no marca pasos: marca advertencias («-VIÑABIKE SE
--   GUARDA EL DERECHO A DIAGNOSTICAR UN POSIBLE CAMBIO DE MAZA»), sub-ítems de
--   un encabezado («Regulación de:» → «- Cadena»), y los `1)` son títulos de
--   sección; los pasos reales («Desarme ⏎ Limpieza ⏎ Engrasado») van sin marca.
--   Ninguna regla de viñetas, `1.` o `1)` separa instrucción de tarea en este
--   catálogo, y las de productos traen promociones con precio («+ Instalación
--   en $45.000»).
--
-- Decisión (Codex y Claude, con la delegación del dueño): la descripción del
-- catálogo es la instrucción de la línea y se muestra como tal («Qué
-- incluye»); una tarea accionable nace sólo de una persona (en la línea o
-- suelta). Por eso:
-- - se retiran el disparador y el parser (con la versión de cinco argumentos
--   que producción conserva y que escribía una columna que ya no existe);
-- - la base rechaza una tarea nueva marcada `parsed_from_description` (el
--   cliente publicado la sigue intentando al guardar una línea: atrapa el
--   error y sigue, sin tarea ruidosa);
-- - las tareas heredadas se conservan con su marca: la app no las muestra como
--   tareas ni las cuenta en el avance, porque repetían la descripción que ahora
--   se muestra entera.
-- El recibo de `save_mechanic_job_lines_v1` sigue trayendo `tasks_created`
-- (los recibos guardados y el cliente publicado lo leen): desde hoy es 0.
--
-- Además (revisión de Codex): la política de inserción de la tabla mira sólo
-- el `tenant_id` de la tarea, y las llaves a trabajo, línea y bici miran sólo
-- sus ids. Una persona del taller B podía crear una tarea suya colgada de un
-- trabajo o de una línea del taller A (reproducido en local). Con cobro no
-- pasaba: la línea que crea `sync_adhoc_task_to_item` choca con la guardia de
-- líneas («Workshop item must belong to the parent job tenant»). Ahora la
-- tarea, su trabajo, su línea, su línea de cobro y su bici tienen que ser del
-- mismo taller y del mismo trabajo. En producción no hay ninguna que no lo
-- cumpla (2026-09-29).
begin;

drop trigger if exists trg_auto_parse_item_description on public.mechanic_job_items;
drop function if exists public.auto_parse_item_description();
drop function if exists public.parse_description_to_tasks(uuid, uuid, uuid, text);
drop function if exists public.parse_description_to_tasks(uuid, uuid, uuid, uuid, text);

create or replace function public.mechanic_job_task_is_explicit()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  -- Una tarea heredada conserva su marca al cambiar otra cosa; lo que no se
  -- admite es crear una o marcar una tarea de persona como heredada.
  if new.parsed_from_description
     and (tg_op = 'INSERT' or not old.parsed_from_description) then
    raise exception 'Las tareas de un trabajo las crea una persona: la descripción del catálogo es instrucción, no tarea'
      using errcode = '23514',
            hint = 'job_task_from_description';
  end if;
  return new;
end;
$function$;

comment on function public.mechanic_job_task_is_explicit() is
  'Rechaza tareas nuevas creadas desde la descripción del catálogo (parsed_from_description). La descripción es instrucción de la línea; una tarea la crea una persona.';

drop trigger if exists trg_mechanic_job_task_is_explicit on public.mechanic_job_tasks;
create trigger trg_mechanic_job_task_is_explicit
  before insert or update of parsed_from_description on public.mechanic_job_tasks
  for each row execute function public.mechanic_job_task_is_explicit();

revoke all on function public.mechanic_job_task_is_explicit()
  from public, anon, authenticated, service_role;

-- La tarea y lo que nombra son del mismo taller y del mismo trabajo. Lee con
-- los derechos del dueño de la función: con los de quien escribe, un trabajo
-- de otro taller es invisible y se leería como «no existe».
create or replace function public.mechanic_job_task_same_tenant()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (
       select 1 from public.mechanic_jobs job
        where job.id = new.job_id and job.tenant_id = new.tenant_id)
     or (new.parent_item_id is not null and not exists (
       select 1 from public.mechanic_job_items item
        where item.id = new.parent_item_id
          and item.tenant_id = new.tenant_id
          and item.job_id = new.job_id))
     or (new.adhoc_item_id is not null and not exists (
       select 1 from public.mechanic_job_items item
        where item.id = new.adhoc_item_id
          and item.tenant_id = new.tenant_id
          and item.job_id = new.job_id))
     or (new.job_bike_id is not null and not exists (
       select 1 from public.mechanic_job_bikes job_bike
        where job_bike.id = new.job_bike_id
          and job_bike.tenant_id = new.tenant_id
          and job_bike.job_id = new.job_id)) then
    raise exception 'La tarea y su trabajo, línea o bici tienen que ser del mismo taller y del mismo trabajo'
      using errcode = '42501',
            hint = 'job_task_other_tenant';
  end if;
  return new;
end;
$function$;

comment on function public.mechanic_job_task_same_tenant() is
  'Una tarea sólo nombra un trabajo, una línea, una línea de cobro o una bici de su mismo taller y de su mismo trabajo.';

drop trigger if exists trg_mechanic_job_task_same_tenant on public.mechanic_job_tasks;
create trigger trg_mechanic_job_task_same_tenant
  before insert or update of tenant_id, job_id, parent_item_id, adhoc_item_id, job_bike_id
  on public.mechanic_job_tasks
  for each row execute function public.mechanic_job_task_same_tenant();

revoke all on function public.mechanic_job_task_same_tenant()
  from public, anon, authenticated, service_role;

comment on column public.mechanic_job_tasks.parsed_from_description is
  'Sólo filas heredadas (hasta 2026-09-29): tareas copiadas de la descripción del catálogo. No se muestran como tareas ni cuentan en el avance; desde 20260929040000 la base no admite nuevas.';

comment on table public.mechanic_job_tasks is
  'Tareas accionables de un trabajo, creadas por una persona: de una línea (parent_item_id) o sueltas (is_standalone); cobrables si is_adhoc. La instrucción de la línea es la descripción de su producto o servicio y sus notas, no una tarea. Quién hace qué y cuándo vive en smart_tasks.';

commit;
