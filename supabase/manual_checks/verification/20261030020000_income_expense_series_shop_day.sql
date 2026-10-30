-- Read-back de 20261030020000: las dos series del panorama comparan los
-- instantes de caja contra la medianoche del taller, toman el mes en curso del
-- reloj del taller y siguen fuera del alcance de `authenticated` y `anon`.

select 1 / case
  when pg_get_functiondef('public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%sp.date >= w.starts_at and sp.date < w.ends_at%'
   and pg_get_functiondef('public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%ea.paid_at >= w.starts_at and ea.paid_at < w.ends_at%'
   and pg_get_functiondef('public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%at time zone shop.zone%'
   and pg_get_functiondef('public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%sp.deleted_at is null%'
   and pg_get_functiondef('public.get_income_expense_timeseries_internal(integer,boolean)'::regprocedure)
         like '%date_trunc(''month'', current_timestamp at time zone shop.zone)%'
   and pg_get_functiondef('public.get_income_expense_timeseries_internal(integer,boolean)'::regprocedure)
         like '%pp.date >= w.starts_at and pp.date < w.ends_at%'
   and pg_get_functiondef('public.get_income_expense_timeseries_internal(integer,boolean)'::regprocedure)
         like '%sp.deleted_at is null%'
   and not has_function_privilege('authenticated', 'public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)', 'execute')
   and not has_function_privilege('anon', 'public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)', 'execute')
   and not has_function_privilege('authenticated', 'public.get_income_expense_timeseries_internal(integer,boolean)', 'execute')
   and not has_function_privilege('anon', 'public.get_income_expense_timeseries_internal(integer,boolean)', 'execute')
  then 1 else 0
end as assert_series_definitions_use_shop_day;

-- Con datos reales: como un miembro del taller principal, cada barra diaria de
-- caja de los últimos 60 días suma lo mismo que los cobros vivos de ese día del
-- taller. Antes de aplicar, el día de un cobro de la noche no calzaba.
select set_config(
  'request.jwt.claim.sub',
  (
    select profile.user_id::text
      from public.user_profiles profile
     where profile.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and profile.is_active is true
       and (
         select count(*)
           from public.user_profiles other
          where other.user_id = profile.user_id
            and other.is_active is true
       ) = 1
     order by profile.created_at
     limit 1
  ),
  true
) is not null as impersonated_tenant_member;

with shop as (
  select tenant.id,
         coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago') as zone
    from public.tenants tenant
   where tenant.id = '5443b130-cc28-45af-a420-cd500b288890'
),
bounds as (
  select (now() at time zone shop.zone)::date - 60 as first_day,
         (now() at time zone shop.zone)::date as last_day
    from shop
),
expected as (
  select (sp.date at time zone shop.zone)::date as day,
         sum(sp.amount) as income
    from public.sales_payments sp
    cross join shop
    cross join bounds
   where sp.tenant_id = shop.id
     and sp.deleted_at is null
     and (sp.date at time zone shop.zone)::date between bounds.first_day and bounds.last_day
   group by 1
),
actual as (
  select series.period_start as day, series.income
    from bounds
    cross join lateral public.get_income_expense_daily_timeseries_internal(
      bounds.first_day::timestamp at time zone 'UTC',
      bounds.last_day::timestamp at time zone 'UTC',
      true
    ) series
),
compared as (
  select coalesce(actual.day, expected.day) as day,
         coalesce(actual.income, 0) as chart_income,
         coalesce(expected.income, 0) as shop_day_income
    from actual
    full join expected on expected.day = actual.day
)
select count(*) as days_compared,
       count(*) filter (where chart_income <> shop_day_income) as mismatched_days,
       min(day) filter (where chart_income <> shop_day_income) as first_mismatch
  from compared;

with shop as (
  select tenant.id,
         coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago') as zone
    from public.tenants tenant
   where tenant.id = '5443b130-cc28-45af-a420-cd500b288890'
),
bounds as (
  select (now() at time zone shop.zone)::date - 60 as first_day,
         (now() at time zone shop.zone)::date as last_day
    from shop
),
expected as (
  select (sp.date at time zone shop.zone)::date as day,
         sum(sp.amount) as income
    from public.sales_payments sp
    cross join shop
    cross join bounds
   where sp.tenant_id = shop.id
     and sp.deleted_at is null
     and (sp.date at time zone shop.zone)::date between bounds.first_day and bounds.last_day
   group by 1
),
actual as (
  select series.period_start as day, series.income
    from bounds
    cross join lateral public.get_income_expense_daily_timeseries_internal(
      bounds.first_day::timestamp at time zone 'UTC',
      bounds.last_day::timestamp at time zone 'UTC',
      true
    ) series
),
compared as (
  select coalesce(actual.income, 0) as chart_income,
         coalesce(expected.income, 0) as shop_day_income
    from actual
    full join expected on expected.day = actual.day
)
select 1 / case
  when count(*) = 61
   and count(*) filter (where chart_income <> shop_day_income) = 0
  then 1 else 0
end as assert_daily_cash_bars_match_shop_days
  from compared;

select 1 / case
  when (
    select max(period_start)
      from public.get_income_expense_timeseries_internal(2, true)
  ) = date_trunc(
    'month',
    current_timestamp at time zone coalesce(
      (select nullif(btrim(timezone), '') from public.tenants
        where id = '5443b130-cc28-45af-a420-cd500b288890'),
      'America/Santiago'
    )
  )::date
  then 1 else 0
end as assert_current_month_is_the_shop_month;
