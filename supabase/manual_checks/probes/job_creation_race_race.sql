-- Connection B: the same creation (same key, same content), as a second
-- window or the outbox resume would send it while A has not committed.
select set_config('request.jwt.claims', '{"sub":"e2870000-0000-4000-8000-000000000091","role":"authenticated"}', false);
select set_config('request.jwt.claim.sub', 'e2870000-0000-4000-8000-000000000091', false);
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as b_sends;
select 'B:' || (public.create_mechanic_job_v1(
  'e2870000-0000-4000-8000-000000000050',
  jsonb_build_object(
    'id', 'e2870000-0000-4000-8000-000000000050',
    'tenant_id', 'e2870000-0000-4000-8000-000000000001',
    'customer_id', 'e2870000-0000-4000-8000-000000000010',
    'bike_id', 'e2870000-0000-4000-8000-000000000020',
    'job_type', 'service', 'workflow_kind', 'service', 'intake_kind', 'bike',
    'mode_needs_review', false, 'arrival_date', '2026-09-29T12:00:00Z',
    'status', 'PENDIENTE', 'priority', 'NORMAL', 'client_request', 'Carrera',
    'estimated_cost', 0, 'final_cost', 0, 'discount_amount', 0,
    'is_invoiced', false, 'is_paid', false, 'is_warranty_job', false,
    'requires_approval', false, 'approved_by_customer', false,
    'image_urls', '[]'::jsonb)) ->> 'replayed') as b_result;
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as b_answered;
