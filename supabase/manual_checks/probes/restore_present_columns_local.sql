-- Prototipo LOCAL del replay R2: preservar la distinción entre una clave
-- ausente (DEFAULT del esquema) y una clave presente con NULL explícito.
-- Sólo acepta una tabla temporal de esta sesión. No es el motor de restore.
begin;

create temporary table restore_present_columns_probe (
  id integer primary key,
  required_value text not null,
  defaulted_value text not null default 'valor-del-servidor',
  nullable_value text
) on commit drop;

create function pg_temp.restore_insert_present_columns(
  p_table regclass,
  p_row jsonb
) returns void
language plpgsql
as $function$
declare
  v_unknown text[];
  v_columns text;
begin
  if not exists (
    select 1 from pg_class c
    where c.oid = p_table and c.relnamespace = pg_my_temp_schema()
  ) then
    raise exception 'La sonda sólo permite tablas temporales'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_row) is distinct from 'object' then
    raise exception 'Cada fila del respaldo debe ser un objeto JSON'
      using errcode = '22023';
  end if;

  select array_agg(k.key order by k.key) into v_unknown
    from jsonb_object_keys(p_row) as k(key)
   where not exists (
     select 1 from pg_attribute a
      where a.attrelid = p_table
        and a.attnum > 0
        and not a.attisdropped
        and a.attgenerated = ''
        and a.attidentity = ''
        and a.attname = k.key
   );
  if v_unknown is not null then
    raise exception 'Columnas incompatibles con el esquema: %', v_unknown
      using errcode = '22023';
  end if;

  select string_agg(format('%I', a.attname), ', ' order by a.attnum)
    into v_columns
    from pg_attribute a
   where a.attrelid = p_table
     and a.attnum > 0
     and not a.attisdropped
     and a.attgenerated = ''
     and a.attidentity = ''
     and p_row ? a.attname;
  if v_columns is null then
    raise exception 'La fila del respaldo no tiene columnas insertables'
      using errcode = '22023';
  end if;

  execute format(
    'insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)',
    p_table, v_columns, v_columns, p_table
  ) using p_row;
end;
$function$;

select pg_temp.restore_insert_present_columns(
  'pg_temp.restore_present_columns_probe'::regclass,
  '{"id":1,"required_value":"conservado"}'::jsonb
);

do $assert$
begin
  begin
    perform pg_temp.restore_insert_present_columns(
      'pg_temp.restore_present_columns_probe'::regclass,
      '{"id":2,"required_value":"conservado","defaulted_value":null}'::jsonb
    );
    raise exception 'NULL explícito pasó la restricción NOT NULL';
  exception when not_null_violation then
    null;
  end;

  begin
    perform pg_temp.restore_insert_present_columns(
      'pg_temp.restore_present_columns_probe'::regclass,
      '{"id":3,"required_value":"conservado","columna_futura":1}'::jsonb
    );
    raise exception 'La columna desconocida fue ignorada';
  exception when invalid_parameter_value then
    null;
  end;
end;
$assert$;

select pg_temp.restore_insert_present_columns(
  'pg_temp.restore_present_columns_probe'::regclass,
  '{"nullable_value":null,"defaulted_value":"del-respaldo","required_value":"conservado","id":4}'::jsonb
);

do $assert$
begin
  if (select count(*) from pg_temp.restore_present_columns_probe) <> 2
     or (select defaulted_value from pg_temp.restore_present_columns_probe
          where id = 1) is distinct from 'valor-del-servidor'
     or (select defaulted_value from pg_temp.restore_present_columns_probe
          where id = 4) is distinct from 'del-respaldo'
     or (select nullable_value from pg_temp.restore_present_columns_probe
          where id = 4) is not null then
    raise exception 'El replay por columnas presentes cambió el resultado';
  end if;
end;
$assert$;

select id, required_value, defaulted_value, nullable_value
  from pg_temp.restore_present_columns_probe order by id;

rollback;
