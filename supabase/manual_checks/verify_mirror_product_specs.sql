-- Read-back de 20260821220000_mirror_product_specs_into_facts.sql

select tgname, tgenabled from pg_trigger
where tgrelid = 'public.product_spec_values'::regclass and not tgisinternal;

select
  -- El trigger existe y esta activo.
  1 / (case when (select count(*) from pg_trigger
        where tgrelid = 'public.product_spec_values'::regclass
          and tgname = 'mirror_product_spec_into_facts'
          and tgenabled = 'O') = 1
      then 1 else 0 end) as afirma_trigger_activo,

  -- Cubre las tres operaciones: sin el DELETE, borrar una ficha dejaria el
  -- hecho vivo en el registro y el espejo mentiria al reves.
  1 / (case when (select count(*) from pg_trigger
        where tgrelid = 'public.product_spec_values'::regclass
          and tgname = 'mirror_product_spec_into_facts'
          and (tgtype & 4) > 0 and (tgtype & 8) > 0 and (tgtype & 16) > 0) = 1
      then 1 else 0 end) as afirma_cubre_insert_update_delete,

  -- Y el espejo esta cuadrado ahora mismo: mismo numero de hechos que de
  -- valores de ficha. Si esto falla, mover un lector perderia datos.
  1 / (case when (select count(*) from public.spec_facts where subject_type = 'product')
        = (select count(*) from public.product_spec_values)
      then 1 else 0 end) as afirma_espejo_cuadrado;
