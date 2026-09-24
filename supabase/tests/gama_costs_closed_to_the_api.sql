begin;

select plan(5);

-- La gama lleva el costo neto promedio de compra de cada marca. Es una vista
-- materializada, sin RLS: con permiso de lectura, anónimo y cualquier tenant
-- leían los costos de todos (20260924020000).

select ok(
  not has_table_privilege('anon', 'public.product_gama_bands_mv', 'SELECT'),
  'anónimo no lee las bandas materializadas'
);
select ok(
  not has_table_privilege('authenticated', 'public.product_gama_bands_mv', 'SELECT'),
  'una sesión no lee las bandas de todos los tenants'
);
select ok(
  not has_table_privilege('anon', 'public.product_gama_v1', 'SELECT'),
  'anónimo no lee la gama vigente'
);
select ok(
  not has_table_privilege('authenticated', 'public.product_gama_v1', 'SELECT'),
  'una sesión no lee la gama vigente de todos los tenants'
);

-- El ranking la lee con los permisos de su dueño, no los de quien llama.
select is(
  (select count(*)::integer
     from pg_proc
    where oid in (
            'public.purchase_candidate_scores_internal_v1'::regproc,
            'public.purchase_supplier_concentration_internal_v1'::regproc)
      and prosecdef),
  2,
  'los consumidores de la gama son SECURITY DEFINER'
);

select * from finish();
rollback;
