-- Read-back of 20261024040000: «camara fv» answers tubes, not what is
-- tubeless. Plain SQL: a missing invariant divides by zero after printing
-- what it found.

select left(r.name, 60) as name, r.category_name
  from public.get_public_products_without_inventory_reservations(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'camara fv', null, false, 'name', 100, 0
  ) r
 where unaccent(lower(concat_ws(' ', r.name, r.category_name, r.category))) !~ 'camara';
select 1 / (case when not exists (
    select 1
      from public.get_public_products_without_inventory_reservations(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'camara fv', null, false, 'name', 100, 0
      ) r
     where unaccent(lower(concat_ws(' ', r.name, r.category_name, r.category))) !~ 'camara'
  ) then 1 else 0 end) as afirma_camara_fv_son_camaras;

select 1 / (case when (select count(*) from public.get_public_products_without_inventory_reservations(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'camara fv', null, false, 'name', 100, 0)) >= 1
  then 1 else 0 end) as afirma_fv_sigue_siendo_francesa;

select 1 / (case when exists (
    select 1 from public.get_public_products_without_inventory_reservations(
      '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'pata de cambio', null, false, 'name', 100, 0) r
     where r.name ilike 'postiza%')
  then 1 else 0 end) as afirma_pata_de_cambio_sigue_siendo_postiza;
