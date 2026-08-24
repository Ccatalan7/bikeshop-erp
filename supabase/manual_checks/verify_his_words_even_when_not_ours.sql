-- Read-back: cuatro escalones, la raíz vive en un solo lugar, y el último
-- escalón exige una palabra de verdad (no una preposición).
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%for v_attempt in 1..4 loop%' then 1 else 0 end) as cuatro_escalones,
  1 / (case when exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'purchase_word_stem_internal_v1'
  ) then 1 else 0 end) as raiz_en_un_lugar,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%length(token) >= 4%' then 1 else 0 end) as palabra_de_verdad,
  -- «platos» y «plato» tienen que tener la misma raíz, o el plural vuelve a
  -- decidir.
  1 / (case when public.purchase_word_stem_internal_v1('platos')
    = 'plato' then 1 else 0 end) as plural_resuelto,
  1 / (case when public.purchase_word_stem_internal_v1('rayos')
    = 'rayo' then 1 else 0 end) as plural_resuelto_2;
