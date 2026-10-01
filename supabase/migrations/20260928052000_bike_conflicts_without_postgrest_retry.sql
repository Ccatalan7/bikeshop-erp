-- Deployment status: NOT DEPLOYED
-- Los conflictos de la ficha dejan de reintentarse solos en PostgREST
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, ítem 3 de la cola).
--
-- `save_bike_aggregate_internal` (4 conflictos: la bici o su ficha cambió o ya
-- no existe) y `patch_bike_technical_facts_v1` (la ficha cambió) avisaban el
-- conflicto con SQLSTATE 40001, `serialization_failure`. PostgREST 14 —el de
-- producción es 14.5— lo toma como transitorio y reintenta la transacción
-- entera, que vuelve a fallar igual: el 2026-09-28, un guardado viejo de la
-- bici fixture de «Test Taller» dejó tres conexiones de PostgREST ejecutando
-- `save_bike_aggregate` sin pausa, la app recibió un 504 del gateway en vez del
-- conflicto, y el bucle sólo paró con `pg_terminate_backend`. Supabase lo
-- documenta («SQLSTATE 40001 in an RPC function causes infinite retries»,
-- corregido en PostgREST 16).
--
-- Se cambia sólo el código: `PT409`, que PostgREST devuelve como HTTP 409 con
-- ese `code`, sin reintentar. Mensajes y `detail` (las claves en conflicto)
-- quedan iguales. El cuerpo se toma de la definición vigente, idéntica en
-- local y producción (md5 92105900… y c4d8003e… al escribir esto), y se
-- exige el número exacto de reemplazos para no tocar otra versión a ciegas.
-- Es reejecutable: con las cinco ya en PT409 no hace nada (revisión de
-- Codex, 2026-09-28; la primera versión fallaba al reaplicarse).
--
-- Clientes ya publicados: el guardado de la bici reconoce por mensaje
-- «changed since it was loaded», pero no «no longer exists»; el parche de la
-- ficha compara `code == '40001'` y verá un rechazo genérico que retiene en
-- memoria. Ninguno escribe de más ni queda en bucle, que es lo que hoy pasa
-- con 40001.
--
-- Otras 77 funciones del esquema usan 40001 igual; quedan fuera de este paso
-- y anotadas en `docs/development/AGENT_DATABASE_CONTRACT.md`.
begin;

do $$
declare
  v_target record;
  v_definition text;
  v_old integer;
  v_new integer;
begin
  for v_target in
    select *
      from (values
        ('public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'::regprocedure, 4),
        ('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure, 1)
      ) as t(fn, expected)
  loop
    v_definition := pg_get_functiondef(v_target.fn);
    v_old := (length(v_definition)
      - length(replace(v_definition, 'errcode = ''serialization_failure''', '')))
      / length('errcode = ''serialization_failure''');
    v_new := (length(v_definition)
      - length(replace(v_definition, 'errcode = ''PT409''', '')))
      / length('errcode = ''PT409''');
    -- Ya corregida: nada que hacer. Un estado a medias o un cuerpo distinto
    -- del esperado detiene la migración.
    if v_old = 0 and v_new = v_target.expected then
      continue;
    end if;
    if v_old <> v_target.expected or v_new <> 0 then
      raise exception '% tiene % conflictos con serialization_failure y % con PT409; se esperaban % y 0, o 0 y %',
        v_target.fn, v_old, v_new, v_target.expected, v_target.expected;
    end if;
    execute replace(
      v_definition,
      'errcode = ''serialization_failure''',
      'errcode = ''PT409'''
    );
  end loop;
end;
$$;

commit;
