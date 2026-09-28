-- Control: the same job finished again, so the same line must write its 28H.
-- A refusal in the race can then never pass for a broken fixture.
update public.mechanic_jobs set status = 'FINALIZADO'
 where id = 'e2790000-0000-4000-8000-000000000051'
   and tenant_id = 'e2790000-0000-4000-8000-000000000001';
