-- Falla si un bloqueo vencido vuelve a cerrar el Portal del Trabajador.
select 1 / (case when
  pg_get_functiondef('public.is_authoritative_worker_portal_identity(uuid,uuid,uuid)'::regprocedure)
    like '%auth_user.banned_until <= statement_timestamp()%'
then 1 else 0 end) as afirma_bloqueo_vencido;
