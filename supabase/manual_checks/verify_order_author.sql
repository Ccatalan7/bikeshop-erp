-- El autor sólo se anota si existe en la tabla a la que apunta la clave
-- foránea. Se comprueba que la función ya no lee `auth.uid()` a ciegas y que
-- `users_profiles` —la tabla legada— sigue vacía para este tenant, que es la
-- razón por la que el pedido no se guardaba.
select
  (select count(*) from public.users_profiles
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890') filas_legadas,
  (select count(*) from public.user_profiles
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890') filas_vigentes,
  position('from public.users_profiles profile' in prosrc) > 0 resuelve_autor
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'save_purchase_order_draft_v1';
