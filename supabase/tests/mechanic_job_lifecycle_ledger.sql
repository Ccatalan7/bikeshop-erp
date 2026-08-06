-- La columna Flujo del taller decía «Sin dato» porque los flags semánticos de
-- job_statuses nunca se ejecutaban y ninguna transición quedaba registrada.
-- Este archivo fija el contrato de captura: cada cambio de estado deja una
-- fila inmutable con fase y flags congelados, el inicio se sella server-side
-- desde cualquier escritor, y el libro es append-only para los clientes.
begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select plan(12);

insert into public.tenants(id,shop_name)
values('99820000-0000-4000-8000-000000000001','Transitions Test');

insert into public.job_statuses(id,tenant_id,name,code,phase,sort_order,triggers_start,triggers_completion,triggers_delivery)
values
 ('99820000-0000-4000-8000-000000000011','99820000-0000-4000-8000-000000000001','Recepción','recepcion','todo',1,false,false,false),
 ('99820000-0000-4000-8000-000000000012','99820000-0000-4000-8000-000000000001','En Curso','en_curso','in_progress',2,true,false,false),
 ('99820000-0000-4000-8000-000000000013','99820000-0000-4000-8000-000000000001','En Pausa','en_pausa','in_progress',3,false,false,false),
 ('99820000-0000-4000-8000-000000000014','99820000-0000-4000-8000-000000000001','Terminado','terminado','complete',4,false,true,false);

insert into public.customers(id,tenant_id,name)
values('99820000-0000-4000-8000-000000000021','99820000-0000-4000-8000-000000000001','Cliente Prueba');

insert into public.mechanic_jobs(id,tenant_id,customer_id,client_request,status,status_id)
values('99820000-0000-4000-8000-000000000031','99820000-0000-4000-8000-000000000001',
       '99820000-0000-4000-8000-000000000021','Ajuste de frenos','Recepción',
       '99820000-0000-4000-8000-000000000011');

-- ── El insert ya deja su primera huella ──────────────────────────────────────
select is(
  (select count(*)::integer from public.mechanic_job_status_transitions
    where job_id='99820000-0000-4000-8000-000000000031'),
  1, 'crear la pega registra la transición inicial');
select is(
  (select to_phase from public.mechanic_job_status_transitions
    where job_id='99820000-0000-4000-8000-000000000031'),
  'todo', 'la fase queda congelada en la fila');
select ok(
  (select from_status is null from public.mechanic_job_status_transitions
    where job_id='99820000-0000-4000-8000-000000000031'),
  'la transición inicial no inventa un estado de origen');

-- ── Pasar a En Curso sella started_at server-side ────────────────────────────
update public.mechanic_jobs
set status='En Curso', status_id='99820000-0000-4000-8000-000000000012'
where id='99820000-0000-4000-8000-000000000031';

select ok(
  (select started_at is not null from public.mechanic_jobs
    where id='99820000-0000-4000-8000-000000000031'),
  'triggers_start ahora sí ejecuta: started_at queda sellado');
select is(
  (select count(*)::integer from public.mechanic_job_status_transitions
    where job_id='99820000-0000-4000-8000-000000000031'),
  2, 'el cambio de estado agrega su fila al libro');
select ok(
  (select to_triggers_start from public.mechanic_job_status_transitions
    where job_id='99820000-0000-4000-8000-000000000031'
    order by occurred_at desc limit 1),
  'la fila congela el flag de inicio vigente ese día');

-- ── Una pausa no des-inicia ni pierde el rastro ──────────────────────────────
create temp table started_before on commit drop as
select started_at from public.mechanic_jobs
where id='99820000-0000-4000-8000-000000000031';

update public.mechanic_jobs
set status='En Pausa', status_id='99820000-0000-4000-8000-000000000013'
where id='99820000-0000-4000-8000-000000000031';

select is(
  (select started_at from public.mechanic_jobs
    where id='99820000-0000-4000-8000-000000000031'),
  (select started_at from started_before),
  'pasar a pausa no borra ni mueve el inicio');

-- ── Terminar sin haber pasado por En Curso igual implica inicio ──────────────
insert into public.mechanic_jobs(id,tenant_id,customer_id,client_request,status,status_id)
values('99820000-0000-4000-8000-000000000032','99820000-0000-4000-8000-000000000001',
       '99820000-0000-4000-8000-000000000021','Cambio de cadena','Recepción',
       '99820000-0000-4000-8000-000000000011');
update public.mechanic_jobs
set status='Terminado', status_id='99820000-0000-4000-8000-000000000014'
where id='99820000-0000-4000-8000-000000000032';

select ok(
  (select started_at is not null and completed_at is not null
    from public.mechanic_jobs
    where id='99820000-0000-4000-8000-000000000032'),
  'un término directo sella inicio y término a la vez');

-- ── Un update sin cambio de estado no ensucia el libro ───────────────────────
update public.mechanic_jobs set client_request='Cambio de cadena y ajuste'
where id='99820000-0000-4000-8000-000000000032';

select is(
  (select count(*)::integer from public.mechanic_job_status_transitions
    where job_id='99820000-0000-4000-8000-000000000032'),
  2, 'editar otros campos no registra transiciones fantasma');

-- ── Append-only: el cliente autenticado no escribe el libro ──────────────────
select set_config('request.jwt.claims',
  '{"sub":"99820000-0000-4000-8000-000000000099","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99820000-0000-4000-8000-000000000099',true);
set local role authenticated;

select throws_ok(
  $$insert into public.mechanic_job_status_transitions
      (tenant_id,job_id,to_status)
    values('99820000-0000-4000-8000-000000000001',
           '99820000-0000-4000-8000-000000000031','Inventado')$$,
  '42501', null,
  'el libro es append-only por trigger: sin insert de cliente');
-- DELETE/UPDATE sin política RLS no fallan: no alcanzan ninguna fila. La
-- aserción correcta es que el libro queda intacto.
delete from public.mechanic_job_status_transitions
where job_id='99820000-0000-4000-8000-000000000031';
update public.mechanic_job_status_transitions set to_status='Alterado';
reset role;

select is(
  (select count(*)::integer from public.mechanic_job_status_transitions
    where job_id='99820000-0000-4000-8000-000000000031'),
  3, 'el delete de cliente no alcanza ninguna fila');
select is(
  (select count(*)::integer from public.mechanic_job_status_transitions
    where to_status='Alterado'),
  0, 'el update de cliente no altera ninguna fila');

select * from finish();
rollback;
