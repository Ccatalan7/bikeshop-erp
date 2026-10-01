-- Sonda LOCAL de replay por diferencia con tablas temporales.
-- Prueba identidad/FK/aislamiento de taller; no prueba triggers de negocio
-- reales, concurrencia ni un restore completo. Siempre termina en ROLLBACK.
begin;

create temporary table restore_diff_parent_probe (
  tenant_id integer not null,
  id integer not null,
  content text not null,
  defaulted_value text not null default 'default-del-esquema',
  primary key (tenant_id, id)
) on commit drop;

create temporary table restore_diff_child_probe (
  tenant_id integer not null,
  id integer not null,
  parent_id integer not null,
  note text not null,
  primary key (tenant_id, id),
  foreign key (tenant_id, parent_id)
    references restore_diff_parent_probe (tenant_id, id)
) on commit drop;

-- Cualquier DELETE del padre se detiene en esta sonda.
create function pg_temp.restore_diff_reject_delete()
returns trigger language plpgsql as $function$
begin
  raise exception 'El replay diferencial no debe borrar padres'
    using errcode = '23503';
end;
$function$;

create trigger restore_diff_reject_delete
before delete on restore_diff_parent_probe
for each row execute function pg_temp.restore_diff_reject_delete();

insert into restore_diff_parent_probe (tenant_id, id, content) values
  (10, 1, 'actualizar'),
  (10, 2, 'vivo-fuera-del-respaldo'),
  (20, 1, 'otro-taller');
insert into restore_diff_child_probe (tenant_id, id, parent_id, note) values
  (10, 1, 1, 'referencia-a-fila-respaldada'),
  (10, 2, 2, 'referencia-fuera-del-respaldo'),
  (20, 1, 1, 'referencia-otro-taller');

create temporary table restore_diff_backup_rows (
  id integer primary key,
  content text not null
) on commit drop;
insert into restore_diff_backup_rows (id, content)
select id, content
from jsonb_to_recordset(
  '[{"id":1,"content":"valor-del-respaldo"},
    {"id":3,"content":"nuevo-del-respaldo"}]'::jsonb
) as row_from_backup(id integer, content text);

create temporary table restore_diff_plan on commit drop as
select coalesce(b.id, live.id) as id,
  case
    when b.id is null then 'preserve_live'
    when live.id is null then 'insert'
    else 'update'
  end as action
from restore_diff_backup_rows b
full join (
  select id from restore_diff_parent_probe where tenant_id = 10
) live using (id);

-- Una fila presente se actualiza por identidad, sin soltar sus hijos.
update restore_diff_parent_probe p
set content = b.content
from restore_diff_backup_rows b
where p.tenant_id = 10 and p.id = b.id;

-- Sólo se insertan ids ausentes. Nombrar columnas permite el DEFAULT.
insert into restore_diff_parent_probe (tenant_id, id, content)
select 10, b.id, b.content
from restore_diff_backup_rows b
where not exists (
  select 1 from restore_diff_parent_probe p
  where p.tenant_id = 10 and p.id = b.id
);

do $assert$
begin
  if (select count(*) from restore_diff_plan where action = 'update') <> 1
     or (select count(*) from restore_diff_plan where action = 'insert') <> 1
     or (select count(*) from restore_diff_plan where action = 'preserve_live') <> 1
     or (select content from restore_diff_parent_probe
         where tenant_id = 10 and id = 1) is distinct from 'valor-del-respaldo'
     or (select content from restore_diff_parent_probe
         where tenant_id = 10 and id = 2) is distinct from 'vivo-fuera-del-respaldo'
     or (select defaulted_value from restore_diff_parent_probe
         where tenant_id = 10 and id = 3) is distinct from 'default-del-esquema'
     or (select content from restore_diff_parent_probe
         where tenant_id = 20 and id = 1) is distinct from 'otro-taller'
     or (select count(*) from restore_diff_child_probe) <> 3 then
    raise exception 'El plan diferencial cambió identidad, hijos o taller';
  end if;
end;
$assert$;

select action, count(*) as rows from restore_diff_plan
group by action order by action;
select tenant_id, id, content, defaulted_value
from restore_diff_parent_probe order by tenant_id, id;

rollback;
