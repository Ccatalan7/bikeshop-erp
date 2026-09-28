-- El cierre de un trabajo consulta si ya existe el recibo de la línea antes
-- de reintentar su parche. La migración 20260927030000 creó la política RLS
-- de lectura, pero revocó SELECT a authenticated: PostgREST devuelve 42501
-- antes de evaluar la política y nunca se aplican los datos instalados.
--
-- Sólo se exponen las tres columnas necesarias para la consulta de existencia.
-- La política existente sigue limitando las filas al único tenant activo del
-- empleado. No se abre applied, result_snapshot ni payload_hash.
-- Reversión, si hiciera falta: REVOKE SELECT (id, tenant_id, operation_key)
-- ON public.bike_technical_fact_patches FROM authenticated;

begin;

grant select (id, tenant_id, operation_key)
  on public.bike_technical_fact_patches to authenticated;

commit;
