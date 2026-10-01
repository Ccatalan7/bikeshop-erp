-- C1 por la app (PLANS.md, 2026-09-30): fixture sintética del recorrido del
-- TaskFormDialog real contra el stack local. La usa
-- scripts/e2e/run_task_form_local.sh por `scripts/db/query.sh local --file`;
-- nunca en otra base.
--
-- El modo llega en la variable de entorno TASK_FORM_E2E_FIXTURE_MODE:
--   setup     el taller sintético y el perfil mechanic de sus dos cuentas
--             (las crea antes el script por la API de Auth)
--   objects   rutas de Storage que quedan bajo ese taller (el script las retira
--             por la API de Storage: los bytes nunca se borran por SQL)
--   readback  lo que dejó el recorrido: una sola tarea pese al reintento,
--             asignada a la compañera; dos vínculos subidos por el empleado,
--             ambos retirados y acusados; nada del archivo abandonado tras
--             el fallo; sin bytes
--   teardown  vínculos, taller (y lo que cuelga de él) y los dos usuarios
--
-- Alcance fijo: taller e2898000-0000-4000-8000-000000000021; el empleado que
-- entra, task-ui-e2e@vinabike.invalid, y la compañera a quien se asigna,
-- task-ui-e2e-otra@vinabike.invalid, ambos mechanic. No toca los talleres
-- …-0001/0002 del recorrido de red (task_attachments_local_fixture.sql).
\set ON_ERROR_STOP on
\getenv fixture_mode TASK_FORM_E2E_FIXTURE_MODE
\if :{?fixture_mode}
\else
select 1 / 0 as falta_task_form_e2e_fixture_mode;
\endif

select :'fixture_mode' = 'setup' as is_setup,
       :'fixture_mode' = 'objects' as is_objects,
       :'fixture_mode' = 'readback' as is_readback,
       :'fixture_mode' = 'teardown' as is_teardown,
       :'fixture_mode' in ('setup', 'objects', 'readback', 'teardown') as is_known
\gset

\if :is_known
\else
select 1 / 0 as modo_desconocido;
\endif

-- Una base con secretos en vault es la de producción: aquí no se sigue.
select 1 / (case when not exists (select 1 from vault.secrets) then 1 else 0 end)
  as solo_base_local
\gset

\if :is_setup
begin;

do $setup$
begin
  if (select count(*) from auth.users
       where lower(email) in ('task-ui-e2e@vinabike.invalid',
                              'task-ui-e2e-otra@vinabike.invalid')) <> 2 then
    raise exception 'Faltan las dos cuentas sintéticas (las crea el script por la API de Auth)';
  end if;
  if exists (select 1 from public.tenants
              where id = 'e2898000-0000-4000-8000-000000000021') then
    raise exception 'Queda el taller sintético de otra corrida: correr antes la retirada';
  end if;
end;
$setup$;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants(id, shop_name) values
  ('e2898000-0000-4000-8000-000000000021', 'TASK UI E2E - SYNTHETIC ONLY');
-- El alta del taller deja su id como `sub` (SUPABASE_WORKFLOW.md).
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.user_profiles(user_id, tenant_id, role)
select account.id, 'e2898000-0000-4000-8000-000000000021', 'mechanic'
  from auth.users account
 where lower(account.email) in ('task-ui-e2e@vinabike.invalid',
                                'task-ui-e2e-otra@vinabike.invalid');

commit;

select profile.tenant_id, profile.role, account.email,
       account.raw_app_meta_data->>'account_type' as account_type,
       account.raw_user_meta_data->>'display_name' as display_name
  from public.user_profiles profile
  join auth.users account on account.id = profile.user_id
 where profile.tenant_id = 'e2898000-0000-4000-8000-000000000021';
\endif

\if :is_objects
select object.name
  from storage.objects object
 where object.bucket_id = 'task-attachments'
   and object.name like 'e2898000-0000-4000-8000-000000000021/%'
 order by object.name;
\endif

\if :is_readback
with employee as (
  select account.id from auth.users account
   where lower(account.email) = 'task-ui-e2e@vinabike.invalid'
), coworker as (
  select account.id from auth.users account
   where lower(account.email) = 'task-ui-e2e-otra@vinabike.invalid'
), task as (
  select smart_task.* from public.smart_tasks smart_task
   where smart_task.tenant_id = 'e2898000-0000-4000-8000-000000000021'
), link as (
  select attachment.* from public.smart_task_attachments attachment
   where attachment.tenant_id = 'e2898000-0000-4000-8000-000000000021'
), facts as (
  select
    (select count(*) from task) as tareas,
    (select count(*) from task where task.created_by = (select id from employee))
      as tareas_del_empleado,
    (select count(*) from task where task.assigned_to = (select id from coworker))
      as asignadas_a_la_companera,
    (select count(*) from link) as vinculos,
    (select count(distinct link.file_name) from link) as archivos_distintos,
    (select count(*) from link where link.uploaded_by = (select id from employee))
      as subidos_por_el_empleado,
    (select count(*) from link
      where link.task_id = (select id from task limit 1)
        and link.storage_path like 'e2898000-0000-4000-8000-000000000021/'
                                   || link.task_id || '/' || link.id || '/%')
      as ruta_del_taller_y_la_tarea,
    (select count(*) from link
      where link.deleted_at is not null and link.storage_deleted_at is not null)
      as retirados_y_acusados,
    (select count(*) from link where link.file_name = 'cadena-estirada.png')
      as vinculos_del_abandonado,
    (select count(*) from storage.objects object
      where object.bucket_id = 'task-attachments'
        and object.name like 'e2898000-0000-4000-8000-000000000021/%') as bytes_restantes
)
select facts.*,
       1 / (case when tareas = 1 and tareas_del_empleado = 1
                  and asignadas_a_la_companera = 1 and vinculos_del_abandonado = 0
                  and vinculos = 2 and archivos_distintos = 2
                  and subidos_por_el_empleado = 2 and ruta_del_taller_y_la_tarea = 2
                  and retirados_y_acusados = 2 and bytes_restantes = 0
                 then 1 else 0 end) as c1_ui_readback
  from facts;
\endif

\if :is_teardown
begin;

do $teardown$
begin
  if exists (select 1 from storage.objects object
              where object.bucket_id = 'task-attachments'
                and object.name like 'e2898000-0000-4000-8000-000000000021/%') then
    raise exception 'Quedan bytes del taller sintético: retirarlos antes por la API de Storage';
  end if;
end;
$teardown$;

delete from public.smart_task_attachments
 where tenant_id = 'e2898000-0000-4000-8000-000000000021';
delete from public.tenants
 where id = 'e2898000-0000-4000-8000-000000000021';
delete from auth.users
 where lower(email) in ('task-ui-e2e@vinabike.invalid',
                        'task-ui-e2e-otra@vinabike.invalid');

commit;

select 1 / (case when not exists (select 1 from public.tenants
                                   where id = 'e2898000-0000-4000-8000-000000000021')
                  and not exists (select 1 from auth.users
                                   where lower(email) in ('task-ui-e2e@vinabike.invalid',
                                                          'task-ui-e2e-otra@vinabike.invalid'))
                  and not exists (select 1 from public.smart_task_attachments
                                   where tenant_id = 'e2898000-0000-4000-8000-000000000021')
                 then 1 else 0 end) as retirada_completa;
\endif
