-- `valve_length_mm` admitia 35/44/60/80 y el catalogo vende 40 y 48.
--
-- 40 mm y 48 mm son los dos largos Presta mas comunes que existen, y hay 4
-- productos vivos con esos valores guardados. Ese vocabulario se escribio de
-- memoria y dejo fuera lo mas vendido: exactamente el mismo defecto que la
-- lista de largos de eje cuadrado, en otra familia y ya desplegado.
--
-- No es cosmetico. `assistant_search_inventory_v7` valida cada valor pedido
-- contra `allowed_values` antes de filtrar, asi que hoy el asistente no puede
-- buscar una camara de valvula 48 aunque la tengas en bodega, y el formulario
-- solo conserva el valor porque lo agrega como opcion suelta al abrirlo.
--
-- Encontrado por la afirmacion de integridad del read-back de
-- 20260820230000_backfill_bottom_bracket_ficha.sql.

begin;

update public.spec_definitions set
  allowed_values = '["35","40","44","48","60","80"]'::jsonb,
  updated_at = now()
where key = 'valve_length_mm' and tenant_id is null;

commit;
