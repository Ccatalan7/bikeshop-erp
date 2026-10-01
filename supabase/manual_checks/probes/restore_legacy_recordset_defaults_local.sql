-- Sonda local y transaccional para el motor legado de restore.
-- Reproduce la diferencia entre insertar un registro completo producido por
-- jsonb_populate_recordset y nombrar las columnas presentes en el respaldo.
-- Sólo crea tablas temporales; nunca ejecutar en producción.
begin;

create temporary table restore_r2_probe (
  id integer primary key,
  required_value text not null,
  defaulted_value text not null default 'valor-del-servidor'
) on commit drop;

create temporary table restore_r2_result (
  legacy_sqlstate text not null,
  recordset_default_is_null boolean not null,
  explicit_insert_default text not null
) on commit drop;

do $probe$
declare
  v_recordset_default text;
  v_legacy_sqlstate text;
begin
  select row.defaulted_value into v_recordset_default
    from jsonb_populate_recordset(
      null::pg_temp.restore_r2_probe,
      '[{"id":1,"required_value":"conservado"}]'::jsonb
    ) as row;

  begin
    insert into pg_temp.restore_r2_probe
    select * from jsonb_populate_recordset(
      null::pg_temp.restore_r2_probe,
      '[{"id":1,"required_value":"conservado"}]'::jsonb
    );
  exception when not_null_violation then
    get stacked diagnostics v_legacy_sqlstate = returned_sqlstate;
  end;

  if v_legacy_sqlstate is distinct from '23502' then
    raise exception 'El insert legado dejó de rechazar la columna ausente';
  end if;

  insert into pg_temp.restore_r2_probe (id, required_value)
  values (1, 'conservado');

  insert into pg_temp.restore_r2_result
  select v_legacy_sqlstate,
         v_recordset_default is null,
         (select defaulted_value from pg_temp.restore_r2_probe where id = 1);
end;
$probe$;

select legacy_sqlstate,
       recordset_default_is_null,
       explicit_insert_default,
       (legacy_sqlstate = '23502'
        and recordset_default_is_null
        and explicit_insert_default = 'valor-del-servidor') as reproduced
  from pg_temp.restore_r2_result;

rollback;
