begin;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select plan(6);

-- Every hour is paid at the hourly rate: attendance never splits a shift into
-- overtime (owner rule 2026-09-10). Before this, a 9,63 h shift produced
-- worked 9,63 + overtime 0,63 and payroll paid the 0,63 twice.
set local session_replication_role = replica;
insert into public.tenants (
  id, shop_name, subdomain, owner_email, timezone, is_active
) values (
  '7f2a3100-0000-4000-8000-000000000001',
  'Flat Hourly Tenant', 'flat-hourly', 'flat-hourly@example.invalid',
  'America/Santiago', true
);
insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title, status,
  hourly_rate, preferred_payment_method
) values (
  '7f2a3100-0000-4000-8000-000000000201',
  '7f2a3100-0000-4000-8000-000000000001',
  'FLAT-001', 'Vicente', 'Prueba', 'Mecánico', 'active', 3500, 'transfer'
);
set local session_replication_role = origin;

-- The shift from the reported week: 14:06 → 23:43, no break.
insert into public.attendances (
  id, tenant_id, employee_id, check_in, check_out, break_minutes, status
) values (
  '7f2a3100-0000-4000-8000-000000000501',
  '7f2a3100-0000-4000-8000-000000000001',
  '7f2a3100-0000-4000-8000-000000000201',
  '2026-09-04 17:06:00+00', '2026-09-05 02:43:00+00', 0, 'ongoing'
);

select is(
  (select worked_hours from public.attendances
    where id = '7f2a3100-0000-4000-8000-000000000501'),
  9.62::numeric,
  'the whole shift lands in worked_hours'
);
select is(
  (select overtime_hours from public.attendances
    where id = '7f2a3100-0000-4000-8000-000000000501'),
  0.00::numeric,
  'a shift longer than nine hours produces no overtime'
);
select is(
  (select status from public.attendances
    where id = '7f2a3100-0000-4000-8000-000000000501'),
  'completed',
  'closing the shift still completes it'
);

-- A client that still sends the old split is corrected on the way in.
update public.attendances
   set overtime_hours = 3, check_out = '2026-09-05 04:06:00+00'
 where id = '7f2a3100-0000-4000-8000-000000000501';
select is(
  (select worked_hours from public.attendances
    where id = '7f2a3100-0000-4000-8000-000000000501'),
  11.00::numeric,
  'extending the shift recomputes worked_hours from the timestamps'
);
select is(
  (select overtime_hours from public.attendances
    where id = '7f2a3100-0000-4000-8000-000000000501'),
  0.00::numeric,
  'overtime written by a client is pinned back to zero'
);

-- A break is still subtracted from the paid hours.
update public.attendances
   set break_minutes = 30
 where id = '7f2a3100-0000-4000-8000-000000000501';
select is(
  (select worked_hours from public.attendances
    where id = '7f2a3100-0000-4000-8000-000000000501'),
  10.50::numeric,
  'the break comes off worked_hours'
);

select * from finish();
rollback;
