-- Falla si alguna de las dos puertas vuelve a tratar un bloqueo vencido como
-- vigente, o si las cuatro que ya estaban bien se rompieron al pasar.
select 1 / (case when
  pg_get_functiondef('public.guard_worker_portal_identity()'::regprocedure)
    like '%banned_until <= statement_timestamp()%'
  and pg_get_functiondef('public.switch_erp_user_to_worker(uuid,uuid,uuid)'::regprocedure)
    like '%banned_until <= statement_timestamp()%'
then 1 else 0 end) as afirma_las_dos_puertas;

select 1 / (case when (
  select count(*)
    from unnest(array[
      'public.erp_member_tenant_id()',
      'public.current_erp_employee_id()',
      'public.get_erp_chat_principal_directory()',
      'public.get_erp_employee_directory()',
      'public.is_authoritative_worker_portal_identity(uuid,uuid,uuid)'
    ]) as f(sig)
   where pg_get_functiondef(f.sig::regprocedure) not like '%statement_timestamp()%'
) = 0 then 1 else 0 end) as afirma_las_que_ya_estaban;
