-- Read-back de 20260821260000_write_goes_to_the_registry.sql

select tgrelid::regclass as tabla, tgname
from pg_trigger where tgname like 'mirror%' and not tgisinternal order by 1;

select
  -- El RPC de guardado existe y es llamable por la app.
  1 / (case when (select count(*) from pg_proc
        where proname = 'save_product_spec_facts_v1') = 1
      then 1 else 0 end) as afirma_rpc_de_guardado,

  1 / (case when has_function_privilege('authenticated',
        'public.save_product_spec_facts_v1(uuid, uuid[], jsonb)', 'execute')
      then 1 else 0 end) as afirma_llamable_por_la_app,

  -- El espejo se dio vuelta: ya no hay trigger escribiendo HACIA spec_facts.
  1 / (case when (select count(*) from pg_trigger
        where tgname = 'mirror_product_spec_into_facts') = 0
      then 1 else 0 end) as afirma_espejo_viejo_retirado,

  -- Y ahora `product_spec_values` se mantiene como copia, para el wizard y la
  -- edicion masiva que todavia la leen.
  1 / (case when (select count(*) from pg_trigger
        where tgname in ('mirror_facts_into_product_specs',
                         'mirror_fact_values_into_product_specs')
          and tgenabled = 'O') = 2
      then 1 else 0 end) as afirma_copia_al_dia,

  -- Sin espejo en las dos direcciones no hay ciclo posible. Se cuentan los
  -- espejos, no todos los triggers: la tabla tiene ademas una validacion de
  -- campos exactos de transmision que es anterior y sigue vigente — ahora
  -- valida tambien lo que escribe la copia, que es lo correcto.
  1 / (case when (select count(*) from pg_trigger t
        where t.tgrelid = 'public.product_spec_values'::regclass
          and not t.tgisinternal and t.tgname like 'mirror%') = 0
      then 1 else 0 end) as afirma_sin_ciclo,

  -- Y las dos formas siguen cuadrando.
  1 / (case when (select count(*) from public.spec_facts where subject_type = 'product')
        = (select count(*) from public.product_spec_values)
      then 1 else 0 end) as afirma_cuadrado;
