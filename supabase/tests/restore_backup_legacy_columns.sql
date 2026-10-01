-- R2 del restore: el motor actual hace INSERT de registros completos, por lo
-- que una clave ausente termina como NULL aunque la columna tenga DEFAULT.
-- Sólo JSON sintético y catálogo local; ninguna fila de negocio se modifica.
begin;
select plan(11);

create temporary table restore_column_fixture as
select jsonb_object_agg(a.attname, '"x"'::jsonb) as full_row
  from pg_catalog.pg_attribute a
 where a.attrelid = 'public.products'::regclass
   and a.attnum > 0
   and not a.attisdropped
   and a.attgenerated = ''
   and (a.attnotnull or a.atthasdef);

select ok(
  to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)')
    is not null,
  'el guard R2 existe'
);

select is(
  public.restore_backup_legacy_column_blocker(
    jsonb_build_object('products', jsonb_build_array(full_row))),
  null::jsonb,
  'una fila con todas las claves relevantes no queda bloqueada'
) from restore_column_fixture;

select is(
  public.restore_backup_legacy_column_blocker(
    jsonb_build_object('products', jsonb_build_array(full_row - 'price')))
      ->> 'reason',
  'missing_default',
  'una columna con DEFAULT omitida se detecta antes del replay'
) from restore_column_fixture;

select is(
  public.restore_backup_legacy_column_blocker(
    jsonb_build_object('products', jsonb_build_array(full_row - 'tenant_id')))
      ->> 'reason',
  'missing_required',
  'una columna obligatoria sin DEFAULT omitida se detecta'
) from restore_column_fixture;

select is(
  public.restore_backup_legacy_column_blocker(
    jsonb_build_object('products', jsonb_build_array(
      jsonb_set(full_row, '{price}', 'null'::jsonb))))
      ->> 'reason',
  'explicit_null',
  'NULL explícito en una columna NOT NULL también se rechaza'
) from restore_column_fixture;

select is(
  public.restore_backup_legacy_column_blocker(
    jsonb_build_object('products', jsonb_build_array(
      jsonb_set(full_row, '{columna_desconocida}', '1'::jsonb))))
      ->> 'reason',
  'unknown_column',
  'una clave desconocida no desaparece silenciosamente'
) from restore_column_fixture;

select is(
  public.restore_backup_legacy_column_blocker(
    '{"products":[]}'::jsonb),
  null::jsonb,
  'una tabla vacía no requiere columnas de fila'
);

select is(
  public.restore_backup_legacy_column_blocker(
    '{"products":[null]}'::jsonb) ->> 'reason',
  'malformed_row',
  'una fila que no es objeto JSON se rechaza'
);

select is(
  public.restore_backup_legacy_column_blocker(
    '{"messages":[{"message_sequence":7}]}'::jsonb) ->> 'reason',
  'identity_replay',
  'un INSERT implícito de una identidad GENERATED ALWAYS queda bloqueado'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.restore_backup_legacy_column_blocker(jsonb)',
    'EXECUTE'
  ),
  'el cliente no puede llamar al helper interno'
);

select ok(
  position('restore_backup_legacy_column_blocker' in
    pg_get_functiondef('public.restore_backup_preflight(uuid,uuid)'::regprocedure)) > 0
  and position('restore_backup_legacy_column_blocker' in
    pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)) > 0,
  'preflight y entrada real consultan el mismo guard'
);

select * from finish();
rollback;
