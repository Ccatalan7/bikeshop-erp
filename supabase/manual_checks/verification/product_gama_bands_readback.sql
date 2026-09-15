-- Read-back de la gama como dato. Falla a nivel SQL si no quedó instalada.
--
-- Sólo afirma lo que instala ESTA migración. Las aserciones del ranking viven
-- en `purchase_ranking_gama_readback.sql`: mezclarlas hizo fallar una
-- verificación por algo que todavía no se había desplegado.

select 1 / (case when to_regclass('public.product_gama_overrides') is null
  then 0 else 1 end) as overrides_table_present;
select 1 / (case when to_regclass('public.product_gama_bands_v1') is null
  then 0 else 1 end) as derived_view_present;
select 1 / (case when to_regclass('public.product_gama_v1') is null
  then 0 else 1 end) as resolved_view_present;

-- La corrección está aislada por tenant: sin RLS, la banda de un taller sería
-- visible por otro.
select 1 / (case when (
  select relrowsecurity from pg_class
   where oid = 'public.product_gama_overrides'::regclass
) then 1 else 0 end) as overrides_rls_enabled;

-- Sólo tres bandas, y ninguna otra palabra.
select 1 / (case when exists (
  select 1 from pg_constraint
   where conrelid = 'public.product_gama_overrides'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) like '%economica%media%alta%'
) then 1 else 0 end) as band_vocabulary_closed;

-- Una marca tiene una sola banda corregida por categoría.
select 1 / (case when exists (
  select 1 from pg_constraint
   where conrelid = 'public.product_gama_overrides'::regclass
     and contype = 'u'
     and pg_get_constraintdef(oid) like '%tenant_id, category_id, brand%'
) then 1 else 0 end) as override_is_unique_per_brand;

-- Con una sola marca no se declara posición de precio: no hay con qué comparar.
select 1 / (case when (
  select count(*) from public.product_gama_bands_v1
   where brands_in_category < 2 and price_position is not null
) = 0 then 1 else 0 end) as no_position_without_comparison;
