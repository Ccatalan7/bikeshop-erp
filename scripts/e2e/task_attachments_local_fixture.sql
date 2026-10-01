-- C1 (PLANS.md, 2026-09-30): fixture sintética del recorrido de adjuntos
-- privados de tareas. La usa scripts/e2e/run_task_attachments_local.sh por
-- `scripts/db/query.sh local --file`; nunca en otra base.
--
-- El modo llega en la variable de entorno TASK_E2E_FIXTURE_MODE:
--   setup     los dos talleres sintéticos y el perfil de cada empleado
--             (los usuarios los crea antes el script por la API de Auth)
--   objects   rutas de Storage que quedan bajo esos talleres (el script las
--             retira por la API de Storage: los bytes nunca se borran por SQL)
--   readback  lo que dejó el recorrido: un vínculo retirado y acusado, sin bytes
--   teardown  vínculos, talleres (y lo que cuelga de ellos) y los dos usuarios
--
-- Alcance fijo: talleres e2898000-…-0001 (A) y …-0002 (B); usuarios
-- task-e2e-a@vinabike.invalid y task-e2e-b@vinabike.invalid, rol mechanic.
\set ON_ERROR_STOP on
\getenv fixture_mode TASK_E2E_FIXTURE_MODE
\if :{?fixture_mode}
\else
select 1 / 0 as falta_task_e2e_fixture_mode;
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
       where lower(email) in ('task-e2e-a@vinabike.invalid', 'task-e2e-b@vinabike.invalid')) <> 2 then
    raise exception 'Faltan los dos usuarios sintéticos (los crea el script por la API de Auth)';
  end if;
  if exists (select 1 from public.tenants
              where id in ('e2898000-0000-4000-8000-000000000001',
                           'e2898000-0000-4000-8000-000000000002')) then
    raise exception 'Quedan talleres sintéticos de otra corrida: correr antes la retirada';
  end if;
end;
$setup$;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants(id, shop_name) values
  ('e2898000-0000-4000-8000-000000000001', 'TASK E2E A - SYNTHETIC ONLY'),
  ('e2898000-0000-4000-8000-000000000002', 'TASK E2E B - SYNTHETIC ONLY');
-- El alta del taller deja su id como `sub` (SUPABASE_WORKFLOW.md).
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.user_profiles(user_id, tenant_id, role)
select account.id, 'e2898000-0000-4000-8000-000000000001', 'mechanic'
  from auth.users account where lower(account.email) = 'task-e2e-a@vinabike.invalid';
insert into public.user_profiles(user_id, tenant_id, role)
select account.id, 'e2898000-0000-4000-8000-000000000002', 'mechanic'
  from auth.users account where lower(account.email) = 'task-e2e-b@vinabike.invalid';

commit;

select profile.tenant_id, profile.role, account.email
  from public.user_profiles profile
  join auth.users account on account.id = profile.user_id
 where profile.tenant_id in ('e2898000-0000-4000-8000-000000000001',
                             'e2898000-0000-4000-8000-000000000002')
 order by account.email;
\endif

\if :is_objects
select object.name
  from storage.objects object
 where object.bucket_id = 'task-attachments'
   and (object.name like 'e2898000-0000-4000-8000-000000000001/%'
        or object.name like 'e2898000-0000-4000-8000-000000000002/%')
 order by object.name;
\endif

\if :is_readback
with link as (
  select attachment.*
    from public.smart_task_attachments attachment
   where attachment.tenant_id = 'e2898000-0000-4000-8000-000000000001'
), facts as (
  select
    (select count(*) from link) as vinculos_taller_a,
    (select count(*) from link
      where link.deleted_at is not null and link.storage_deleted_at is not null)
      as retirados_y_acusados,
    (select count(*) from link
       join auth.users account on account.id = link.uploaded_by
      where lower(account.email) = 'task-e2e-a@vinabike.invalid') as subidos_por_empleado_a,
    (select count(*) from link
      where link.storage_path like 'e2898000-0000-4000-8000-000000000001/%') as ruta_del_taller_a,
    (select count(*) from public.smart_task_attachments attachment
      where attachment.tenant_id = 'e2898000-0000-4000-8000-000000000002') as vinculos_taller_b,
    (select count(*) from storage.objects object
      where object.bucket_id = 'task-attachments'
        and (object.name like 'e2898000-0000-4000-8000-000000000001/%'
             or object.name like 'e2898000-0000-4000-8000-000000000002/%')) as bytes_restantes
)
select facts.*,
       1 / (case when vinculos_taller_a = 1 and retirados_y_acusados = 1
                  and subidos_por_empleado_a = 1 and ruta_del_taller_a = 1
                  and vinculos_taller_b = 0 and bytes_restantes = 0
                 then 1 else 0 end) as c1_readback
  from facts;
\endif

\if :is_teardown
begin;

do $teardown$
begin
  if exists (select 1 from storage.objects object
              where object.bucket_id = 'task-attachments'
                and (object.name like 'e2898000-0000-4000-8000-000000000001/%'
                     or object.name like 'e2898000-0000-4000-8000-000000000002/%')) then
    raise exception 'Quedan bytes de los talleres sintéticos: retirarlos antes por la API de Storage';
  end if;
end;
$teardown$;

delete from public.smart_task_attachments
 where tenant_id in ('e2898000-0000-4000-8000-000000000001',
                     'e2898000-0000-4000-8000-000000000002');
delete from public.tenants
 where id in ('e2898000-0000-4000-8000-000000000001',
              'e2898000-0000-4000-8000-000000000002');
delete from auth.users
 where lower(email) in ('task-e2e-a@vinabike.invalid', 'task-e2e-b@vinabike.invalid');

commit;

select 1 / (case when not exists (select 1 from public.tenants
                                   where id in ('e2898000-0000-4000-8000-000000000001',
                                                'e2898000-0000-4000-8000-000000000002'))
                  and not exists (select 1 from auth.users
                                   where lower(email) in ('task-e2e-a@vinabike.invalid',
                                                          'task-e2e-b@vinabike.invalid'))
                  and not exists (select 1 from public.smart_task_attachments
                                   where tenant_id in ('e2898000-0000-4000-8000-000000000001',
                                                       'e2898000-0000-4000-8000-000000000002'))
                 then 1 else 0 end) as retirada_completa;
\endif
