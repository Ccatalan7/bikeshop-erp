begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(25);

select has_column(
  'public', 'mechanic_jobs', 'actual_labor_hours',
  'jobs capture explicit real labor hours'
);
select has_function(
  'public', 'get_strategic_dashboard_metrics',
  array['timestamp with time zone', 'timestamp with time zone'],
  'the strategic dashboard has one tenant-scoped read model'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_strategic_dashboard_metrics(timestamp with time zone,timestamp with time zone)',
    'execute'
  ),
  'authenticated staff can read strategic metrics'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_strategic_dashboard_metrics(timestamp with time zone,timestamp with time zone)',
    'execute'
  ),
  'anonymous callers cannot read strategic metrics'
);
select has_function(
  'public', 'get_mechanic_job_time_metrics', array['uuid[]'],
  'workshop rows share one provenance-aware lifecycle read model'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_mechanic_job_time_metrics(uuid[])',
    'execute'
  ),
  'authenticated staff can read canonical job time evidence'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_mechanic_job_time_metrics(uuid[])',
    'execute'
  ),
  'anonymous callers cannot read job time evidence'
);

insert into public.tenants(id, shop_name, timezone) values (
  'a7170000-0000-4000-8000-000000000001',
  'Strategic KPI Tenant',
  'America/Santiago'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a7170000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'strategic-dashboard@example.invalid', '',
  now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', 'a7170000-0000-4000-8000-000000000001'
  ),
  now(), now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  'a7170000-0000-4000-8000-000000000099',
  'a7170000-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'a7170000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a7170000-0000-4000-8000-000000000099',
  true
);

insert into public.website_settings(tenant_id, key, value)
values (
  'a7170000-0000-4000-8000-000000000001',
  'business_hours_json',
  '{"periods":[{"open":{"day":1,"time":"0900"},"close":{"day":1,"time":"1700"}},{"open":{"day":2,"time":"0900"},"close":{"day":2,"time":"1700"}},{"open":{"day":3,"time":"0900"},"close":{"day":3,"time":"1700"}},{"open":{"day":4,"time":"0900"},"close":{"day":4,"time":"1700"}},{"open":{"day":5,"time":"0900"},"close":{"day":5,"time":"1700"}}]}'
)
on conflict (tenant_id, key) do update set value = excluded.value;

insert into public.customers(id, tenant_id, name) values (
  'a7170000-0000-4000-8000-000000000011',
  'a7170000-0000-4000-8000-000000000001',
  'Strategic KPI Customer'
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, is_active
) values
(
  'a7170000-0000-4000-8000-000000000021',
  'a7170000-0000-4000-8000-000000000001',
  'Strategic KPI Product', 'STRATEGIC-KPI-001', 119000, 50000,
  'product', false, true, 10, 10, true
),
(
  'a7170000-0000-4000-8000-000000000022',
  'a7170000-0000-4000-8000-000000000001',
  'Strategic KPI Service', 'STRATEGIC-KPI-SERVICE', 119000, 0,
  'service', true, false, 0, 0, true
);

insert into public.employees(
  id, tenant_id, employee_number, first_name, last_name, email, job_title,
  status, hire_date, hourly_rate
) values (
  'a7170000-0000-4000-8000-000000000031',
  'a7170000-0000-4000-8000-000000000001',
  'KPI-001',
  'Mecánico', 'KPI', 'mechanic-kpi@example.invalid', 'Mecánico',
  'active', '2026-01-01', 4000
);

insert into public.attendances(
  id, tenant_id, employee_id, check_in, check_out,
  worked_hours, break_minutes, status
) values (
  'a7170000-0000-4000-8000-000000000041',
  'a7170000-0000-4000-8000-000000000001',
  'a7170000-0000-4000-8000-000000000031',
  '2026-07-06 09:00:00-04', '2026-07-06 19:00:00-04',
  10, 0, 'approved'
);

insert into public.payroll_vouchers(
  id, tenant_id, voucher_number, period_start, period_end,
  period_label, total_hours, total_amount, employee_count, status, paid_at
) values (
  'a7170000-0000-4000-8000-000000000051',
  'a7170000-0000-4000-8000-000000000001',
  'PV-STRATEGIC-KPI', '2026-07-06', '2026-07-06',
  'KPI fixture', 10, 40000, 1, 'paid', '2026-07-06 20:00:00-04'
);

insert into public.payroll_voucher_lines(
  id, tenant_id, voucher_id, employee_id, employee_name,
  worked_hours, hourly_rate, regular_amount, total_amount, is_included
) values (
  'a7170000-0000-4000-8000-000000000061',
  'a7170000-0000-4000-8000-000000000001',
  'a7170000-0000-4000-8000-000000000051',
  'a7170000-0000-4000-8000-000000000031',
  'Mecánico KPI', 10, 4000, 40000, 40000, true
);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, date, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  'a7170000-0000-4000-8000-000000000071',
  'a7170000-0000-4000-8000-000000000001',
  'FV-STRATEGIC-KPI',
  'a7170000-0000-4000-8000-000000000011',
  '2026-07-06 16:00:00-04', 'paid',
  320000, 320000, 60800, 380800, 380800, 0,
  'tax_included',
  jsonb_build_array(
    jsonb_build_object(
      'product_id', 'a7170000-0000-4000-8000-000000000021',
      'product_name', 'Strategic KPI Product',
      'quantity', 2, 'line_total', 238000, 'cost', 50000,
      'is_service', false, 'item_type', 'product'
    ),
    jsonb_build_object(
      'product_id', 'a7170000-0000-4000-8000-000000000022',
      'product_name', 'Strategic KPI Service',
      'quantity', 1, 'line_total', 119000, 'cost', 0,
      'is_service', true, 'item_type', 'service'
    ),
    jsonb_build_object(
      'product_name', 'Strategic KPI Unclassified',
      'quantity', 1, 'line_total', 23800, 'cost', 0
    )
  )
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status, arrival_date
) values (
  'a7170000-0000-4000-8000-000000000082',
  'a7170000-0000-4000-8000-000000000001',
  'a7170000-0000-4000-8000-000000000011',
  'PG-STRATEGIC-LEGACY', 'item_service', 'service', 'component',
  'FINALIZADO', '2026-07-07 09:00:00-04'
);

insert into public.mechanic_job_timeline(
  id, tenant_id, job_id, event_type, new_value, created_at
) values
(
  'a7170000-0000-4000-8000-000000000091',
  'a7170000-0000-4000-8000-000000000001',
  'a7170000-0000-4000-8000-000000000082',
  'status_changed', 'COMENZAR', '2026-07-07 10:00:00-04'
),
(
  'a7170000-0000-4000-8000-000000000092',
  'a7170000-0000-4000-8000-000000000001',
  'a7170000-0000-4000-8000-000000000082',
  'status_changed', 'FINALIZADO', '2026-07-07 12:00:00-04'
);

insert into public.mechanic_job_delivery_events(
  id, tenant_id, job_id, event_kind, occurred_at, recorded_at,
  source, source_timeline_id, operation_key
) values (
  'a7170000-0000-4000-8000-000000000093',
  'a7170000-0000-4000-8000-000000000001',
  'a7170000-0000-4000-8000-000000000082',
  'delivered', '2026-07-07 14:00:00-04', '2026-07-07 14:00:00-04',
  'legacy_timeline', 'a7170000-0000-4000-8000-000000000092',
  'strategic-kpi-legacy-delivery'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status, arrival_date, started_at, completed_at,
  invoice_id, is_invoiced, actual_labor_hours, estimated_duration_hours
) values (
  'a7170000-0000-4000-8000-000000000081',
  'a7170000-0000-4000-8000-000000000001',
  'a7170000-0000-4000-8000-000000000011',
  'PG-STRATEGIC-KPI', 'item_service', 'service', 'component',
  'FINALIZADO', '2026-07-06 09:00:00-04',
  '2026-07-06 10:00:00-04', '2026-07-06 15:00:00-04',
  'a7170000-0000-4000-8000-000000000071', true, 5, 5
);

create temporary table strategic_result as
select public.get_strategic_dashboard_metrics(
  '2026-07-06 00:00:00-04',
  '2026-07-13 00:00:00-04'
) as value;

select is(
  round((value #>> '{value,serviceSales}')::numeric),
  100000::numeric,
  'service lines are separated and normalized to net sales'
) from strategic_result;
select is(
  round((value #>> '{value,productSales}')::numeric),
  200000::numeric,
  'product lines are separated and normalized to net sales'
) from strategic_result;
select is(
  round((value #>> '{value,unclassifiedSales}')::numeric),
  20000::numeric,
  'ambiguous lines remain visible and are not counted as products'
) from strategic_result;
select is(
  round((value #>> '{value,classificationCoverageRate}')::numeric, 4),
  0.9375::numeric,
  'sales classification coverage is exposed explicitly'
) from strategic_result;
select is(
  round((value #>> '{value,productGrossMarginRate}')::numeric, 2),
  0.50::numeric,
  'product gross margin uses the historical line cost'
) from strategic_result;
select is(
  round((value #>> '{value,businessOpenHours}')::numeric),
  40::numeric,
  'business capacity comes from the configured opening hours'
) from strategic_result;
select is(
  round((value #>> '{value,mechanicAttendanceHours}')::numeric),
  10::numeric,
  'mechanic presence comes from attendance sessions'
) from strategic_result;
select is(
  round((value #>> '{value,actualHours}')::numeric),
  5::numeric,
  'productive hours come only from explicit job labor hours'
) from strategic_result;
select is(
  round((value #>> '{value,productiveUtilizationRate}')::numeric, 2),
  0.50::numeric,
  'productive utilization compares job hours against attendance hours'
) from strategic_result;
select is(
  round((value #>> '{value,mechanicCostUsed}')::numeric),
  40000::numeric,
  'mechanic cost prefers backed paid payroll lines'
) from strategic_result;
select is(
  round((value #>> '{value,laborContribution}')::numeric),
  60000::numeric,
  'labor contribution excludes products and subtracts mechanic cost'
) from strategic_result;
select is(
  value #>> '{value,mechanicCostSource}',
  'paid_payroll',
  'the metric discloses the mechanic cost source'
) from strategic_result;

create temporary table time_result as
select * from public.get_mechanic_job_time_metrics(array[
  'a7170000-0000-4000-8000-000000000082'::uuid
]);

select is(
  start_source,
  'legacy_timeline',
  'a missing start timestamp is reconstructed from the status timeline'
) from time_result;
select is(
  completion_source,
  'legacy_timeline',
  'a missing completion timestamp is reconstructed from the status timeline'
) from time_result;
select is(
  first_delivered_at,
  '2026-07-07 14:00:00-04'::timestamptz,
  'cycle time stops at the first immutable delivery event'
) from time_result;
select is(
  delivery_source,
  'legacy_timeline',
  'delivery provenance remains visible'
) from time_result;
select ok(
  reopened_after_delivery,
  'a job no longer in delivered state is identified as reopened'
) from time_result;
select ok(
  quality_flags @> array[
    'start_reconstructed_from_timeline',
    'completion_reconstructed_from_timeline',
    'delivery_reconstructed_from_legacy_event'
  ]::text[],
  'legacy reconstruction is disclosed through quality flags'
) from time_result;

select * from finish();
rollback;
