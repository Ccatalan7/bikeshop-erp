-- General temporal analytics and relational workshop context for the AI agent.
-- Relative ranges are resolved from the tenant business date. Workshop
-- identity is server-owned across customer, every bike and the linked invoice.

begin;

create or replace function public.assistant_capabilities_internal_v2(
  p_profile_role text,
  p_authority_role text,
  p_permissions jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_permissions jsonb := coalesce(p_permissions, '{}'::jsonb);
  v_capabilities text[] := array['ai.read.operational']::text[];
begin
  if p_authority_role in ('owner', 'admin', 'manager', 'cashier', 'accountant')
     or v_permissions @> '{"create_invoices":true}'::jsonb
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.sales');
  end if;
  if p_authority_role in ('owner', 'admin', 'manager', 'accountant')
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.purchases');
  end if;
  if p_profile_role in ('admin', 'manager', 'accountant')
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.accounting');
  end if;
  if p_profile_role in ('owner', 'admin', 'manager', 'mechanic') then
    v_capabilities := array_append(v_capabilities, 'ai.write.workshop');
  end if;
  return to_jsonb(v_capabilities);
end;
$$;

revoke all on function public.assistant_capabilities_internal_v2(
  text, text, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.assistant_query_workshop_jobs_v3(
  p_query text,
  p_horizon text,
  p_status text,
  p_priority text,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_query text;
  v_timezone text;
  v_business_date date;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) > 240
     or p_horizon not in ('any', 'today', 'tomorrow', 'week', 'overdue')
     or p_status not in ('any', 'open', 'completed', 'delivered', 'cancelled')
     or p_priority not in ('any', 'urgent', 'high', 'normal', 'low')
     or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
  into strict v_timezone
  from public.tenants tenant
  where tenant.id = v_authority.tenant_id and tenant.is_active is true;
  if not exists (select 1 from pg_timezone_names zone where zone.name = v_timezone) then
    raise exception 'Tenant timezone is invalid' using errcode = '42501';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_business_date := (statement_timestamp() at time zone v_timezone)::date;

  with bike_context as materialized (
    select job_bike.job_id,
      count(*)::integer bike_count,
      string_agg(
        nullif(btrim(concat_ws(' ', bike.brand, bike.model,
          case when bike.year is null then null else bike.year::text end)), ''),
        ' | ' order by job_bike.order_index, job_bike.id
      ) bike_summary
    from public.mechanic_job_bikes job_bike
    join public.bikes bike
      on bike.id = job_bike.bike_id and bike.tenant_id = job_bike.tenant_id
    where job_bike.tenant_id = v_authority.tenant_id
    group by job_bike.job_id
  ), candidates as materialized (
    select job.id entity_id, job.job_number, customer.name customer_name,
      coalesce(status.name, job.status) status_name,
      case
        when upper(coalesce(status.code, job.status, '')) in (
          'CANCELADO','CANCELADA','ANULADO','ANULADA','CANCELLED','CANCELED'
        ) then 'cancelled'
        when job.delivered_at is not null or coalesce(status.triggers_delivery, false)
          or upper(coalesce(status.code, job.status, '')) in ('ENTREGADO','ENTREGADA','DELIVERED')
          then 'delivered'
        when job.completed_at is not null or coalesce(status.phase, 'in_progress') = 'complete'
          or upper(coalesce(status.code, job.status, '')) in (
            'COMPLETADO','COMPLETADA','FINALIZADO','FINALIZADA','COMPLETED','COMPLETE'
          ) then 'completed'
        else 'open'
      end lifecycle_status,
      case upper(coalesce(job.priority, 'NORMAL'))
        when 'URGENTE' then 'urgent' when 'ALTA' then 'high'
        when 'BAJA' then 'low' else 'normal' end normalized_priority,
      job.priority, job.arrival_date, job.deadline, job.client_request,
      job.updated_at, invoice.invoice_number,
      coalesce(bike_context.bike_summary,
        nullif(btrim(concat_ws(' ', primary_bike.brand, primary_bike.model,
          case when primary_bike.year is null then null else primary_bike.year::text end)), '')
      ) bike_summary,
      coalesce(bike_context.bike_count, case when primary_bike.id is null then 0 else 1 end)
        bike_count
    from public.mechanic_jobs job
    join public.customers customer
      on customer.id = job.customer_id and customer.tenant_id = job.tenant_id
    left join public.bikes primary_bike
      on primary_bike.id = job.bike_id and primary_bike.tenant_id = job.tenant_id
    left join bike_context on bike_context.job_id = job.id
    left join public.sales_invoices invoice
      on invoice.id = job.invoice_id and invoice.tenant_id = job.tenant_id
    left join public.job_statuses status
      on status.id = job.status_id and status.tenant_id = job.tenant_id
    where job.tenant_id = v_authority.tenant_id and job.deleted_at is null
  ), matched as materialized (
    select candidates.entity_id, candidates.job_number,
      candidates.customer_name, candidates.status_name,
      candidates.lifecycle_status, candidates.normalized_priority,
      candidates.priority, candidates.arrival_date, candidates.deadline,
      candidates.client_request, candidates.updated_at,
      candidates.invoice_number, candidates.bike_summary,
      candidates.bike_count
    from candidates
    where (p_status = 'any' or lifecycle_status = p_status)
      and (p_priority = 'any' or normalized_priority = p_priority)
      and case p_horizon
        when 'any' then true
        when 'overdue' then deadline is not null
          and (deadline at time zone v_timezone)::date < v_business_date
        when 'today' then deadline is not null
          and (deadline at time zone v_timezone)::date = v_business_date
        when 'tomorrow' then deadline is not null
          and (deadline at time zone v_timezone)::date = v_business_date + 1
        when 'week' then deadline is not null
          and (deadline at time zone v_timezone)::date
            between v_business_date and v_business_date + 6
        else false end
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', job_number, customer_name, status_name, priority,
            client_request, invoice_number, bike_summary)
        )) = 0
      ))
    order by (deadline is null), deadline,
      case normalized_priority when 'urgent' then 0 when 'high' then 1
        when 'normal' then 2 else 3 end,
      updated_at desc, job_number, entity_id
    limit p_limit + 1
  ), numbered as (
    select matched.entity_id, matched.job_number, matched.customer_name,
      matched.status_name, matched.lifecycle_status,
      matched.normalized_priority, matched.priority, matched.arrival_date,
      matched.deadline, matched.client_request, matched.updated_at,
      matched.invoice_number, matched.bike_summary, matched.bike_count,
      row_number() over (order by (deadline is null), deadline,
      case normalized_priority when 'urgent' then 0 when 'high' then 1
        when 'normal' then 2 else 3 end,
      updated_at desc, job_number, entity_id) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'jobNumber', public.assistant_truncate_utf8_internal_v1(job_number, 80),
      'customerName', public.assistant_truncate_utf8_internal_v1(customer_name, 160),
      'status', public.assistant_truncate_utf8_internal_v1(status_name, 100),
      'priority', public.assistant_truncate_utf8_internal_v1(priority, 40),
      'arrivalDate', arrival_date,
      'deliveryDeadline', deadline,
      'clientRequest', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(client_request, ''), 500), ''),
      'assignedTechnicianName', null,
      'invoiceNumber', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(invoice_number, ''), 100), ''),
      'bikeSummary', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(bike_summary, ''), 240), ''),
      'bikeCount', bike_count
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

create or replace function public.assistant_get_workshop_job_context_v1(
  p_job_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_items jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.operational') authority;
  if p_job_id is null then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  with job_context as materialized (
    select job.id, job.job_number, job.job_type, job.updated_at,
      customer.name customer_name, coalesce(status.name, job.status) job_status,
      case
        when job.deleted_at is not null or job.delivered_at is not null
          or job.completed_at is not null
          or coalesce(status.phase, 'in_progress') = 'complete'
          or coalesce(status.triggers_delivery, false)
          or upper(coalesce(status.code, job.status, '')) in (
            'CANCELADO','CANCELADA','ANULADO','ANULADA','CANCELLED','CANCELED',
            'ENTREGADO','ENTREGADA','DELIVERED','COMPLETADO','COMPLETADA',
            'FINALIZADO','FINALIZADA','COMPLETED','COMPLETE'
          ) then false else true end job_is_mutable,
      invoice.id invoice_id, invoice.invoice_number, invoice.status invoice_status,
      case when invoice.id is null then false else (
        lower(coalesce(invoice.status, '')) in ('paid','pagado','pagada')
        or coalesce(invoice.paid_amount, 0) > 0
        or exists (select 1 from public.sales_payments payment
          where payment.tenant_id = invoice.tenant_id
            and payment.invoice_id = invoice.id and payment.deleted_at is null
            and payment.amount > 0)
      ) end has_financial_history
    from public.mechanic_jobs job
    join public.customers customer
      on customer.id = job.customer_id and customer.tenant_id = job.tenant_id
    left join public.job_statuses status
      on status.id = job.status_id and status.tenant_id = job.tenant_id
    left join public.sales_invoices invoice
      on invoice.id = job.invoice_id and invoice.tenant_id = job.tenant_id
    where job.id = p_job_id and job.tenant_id = v_authority.tenant_id
      and job.deleted_at is null
  ), rows as (
    select context.id, context.job_number, context.job_type,
      context.updated_at, context.customer_name, context.job_status,
      context.job_is_mutable, context.invoice_id, context.invoice_number,
      context.invoice_status, context.has_financial_history,
      job_bike.id job_bike_id,
      job_bike.diagnosis_sheet_updated_at,
      nullif(btrim(concat_ws(' ', bike.brand, bike.model,
        case when bike.year is null then null else bike.year::text end)), '') bike_label
    from job_context context
    left join public.mechanic_job_bikes job_bike
      on job_bike.job_id = context.id and job_bike.tenant_id = v_authority.tenant_id
    left join public.bikes bike
      on bike.id = job_bike.bike_id and bike.tenant_id = v_authority.tenant_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'entityId', id,
    'jobBikeId', job_bike_id,
    'jobNumber', public.assistant_truncate_utf8_internal_v1(job_number, 80),
    'customerName', public.assistant_truncate_utf8_internal_v1(customer_name, 160),
    'bikeLabel', nullif(public.assistant_truncate_utf8_internal_v1(
      coalesce(bike_label, ''), 200), ''),
    'jobType', public.assistant_truncate_utf8_internal_v1(job_type, 40),
    'jobStatus', public.assistant_truncate_utf8_internal_v1(job_status, 100),
    'jobUpdatedAt', updated_at,
    'invoiceId', invoice_id,
    'invoiceNumber', nullif(public.assistant_truncate_utf8_internal_v1(
      coalesce(invoice_number, ''), 100), ''),
    'invoiceStatus', nullif(public.assistant_truncate_utf8_internal_v1(
      coalesce(invoice_status, ''), 40), ''),
    'diagnosisUpdatedAt', diagnosis_sheet_updated_at,
    'canUpdateDiagnosis', job_is_mutable and job_bike_id is not null,
    'canAddWorkshopItem', job_is_mutable and not has_financial_history
  ) order by job_bike_id), '[]'::jsonb)
  into v_items from rows;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, false
  );
end;
$$;

create or replace function public.assistant_diagnosis_field_registry_internal_v1()
returns table (
  section_key text,
  json_key text,
  label text,
  value_type text,
  stored_unit text,
  input_units text,
  allowed_values text,
  minimum_value numeric,
  maximum_value numeric
)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select registry.section_key, registry.json_key, registry.label,
    registry.value_type, registry.stored_unit, registry.input_units,
    registry.allowed_values, registry.minimum_value, registry.maximum_value
  from (values
    ('suspension','overall_status','Estado general suspensión','text','none','none','ok,attention,critical,unknown',null::numeric,null::numeric),
    ('suspension','fork_condition','Estado horquilla','text','none','none','ok,rough,sticky,leaking,play,service,replace',null,null),
    ('suspension','fork_noise_status','Ruido horquilla','text','none','none','ok,creaking,clicking,knocking,service',null,null),
    ('suspension','rear_shock_condition','Estado amortiguador trasero','text','none','none','ok,rough,sticky,leaking,play,service,replace',null,null),
    ('suspension','rear_shock_noise_status','Ruido amortiguador trasero','text','none','none','ok,creaking,clicking,knocking,service',null,null),
    ('suspension','notes','Notas suspensión','text','none','none',null,null,null),
    ('drivetrain','overall_status','Estado general transmisión','text','none','none','ok,attention,critical,unknown',null,null),
    ('drivetrain','chain_wear_percent','Desgaste de cadena','number','percent','display_fraction,percent',null,0,100),
    ('drivetrain','cable_condition','Estado cables y fundas','text','none','none','ok,high_friction,frayed,corroded,housing_damaged,replace',null,null),
    ('drivetrain','chain_lubrication_status','Lubricación cadena','text','none','none','ok,dry,dirty,contaminated',null,null),
    ('drivetrain','cassette_condition','Estado cassette','text','none','none','ok,attention,worn,replace',null,null),
    ('drivetrain','chainring_condition','Estado plato','text','none','none','ok,attention,worn,replace',null,null),
    ('drivetrain','rear_derailleur_condition','Estado cambio trasero','text','none','none','ok,attention,bent,replace',null,null),
    ('drivetrain','front_derailleur_condition','Estado cambio delantero','text','none','none','ok,attention,bent,replace',null,null),
    ('drivetrain','shifter_condition','Estado shifter','text','none','none','ok,sticky,attention,replace',null,null),
    ('drivetrain','notes','Notas transmisión','text','none','none',null,null,null),
    ('front_brake','overall_status','Estado general freno delantero','text','none','none','ok,attention,critical,unknown',null,null),
    ('front_brake','pad_wear_percent','Desgaste pastillas delanteras','number','percent','display_fraction,percent',null,0,100),
    ('front_brake','pad_contamination_status','Contaminación pastillas delanteras','text','none','none','ok,dirty,contaminated,replace',null,null),
    ('front_brake','rotor_thickness_mm','Espesor rotor delantero','number','millimeter','millimeter',null,0,20),
    ('front_brake','rotor_trueness_status','Alineación rotor delantero','text','none','none','ok,attention,misaligned,replace',null,null),
    ('front_brake','rotor_contamination_status','Contaminación rotor delantero','text','none','none','ok,dirty,contaminated,replace',null,null),
    ('front_brake','notes','Notas freno delantero','text','none','none',null,null,null),
    ('rear_brake','overall_status','Estado general freno trasero','text','none','none','ok,attention,critical,unknown',null,null),
    ('rear_brake','pad_wear_percent','Desgaste pastillas traseras','number','percent','display_fraction,percent',null,0,100),
    ('rear_brake','pad_contamination_status','Contaminación pastillas traseras','text','none','none','ok,dirty,contaminated,replace',null,null),
    ('rear_brake','rotor_thickness_mm','Espesor rotor trasero','number','millimeter','millimeter',null,0,20),
    ('rear_brake','rotor_trueness_status','Alineación rotor trasero','text','none','none','ok,attention,misaligned,replace',null,null),
    ('rear_brake','rotor_contamination_status','Contaminación rotor trasero','text','none','none','ok,dirty,contaminated,replace',null,null),
    ('rear_brake','notes','Notas freno trasero','text','none','none',null,null,null),
    ('front_wheel','overall_status','Estado general rueda delantera','text','none','none','ok,attention,critical,unknown',null,null),
    ('front_wheel','tire_condition','Estado cubierta delantera','text','none','none','ok,worn,damaged,replace',null,null),
    ('front_wheel','rim_condition','Estado aro delantero','text','none','none','ok,attention,bent,cracked,replace',null,null),
    ('front_wheel','spoke_condition','Estado rayos delanteros','text','none','none','ok,loose,uneven,broken',null,null),
    ('front_wheel','hub_bearing_condition','Rodamientos maza delantera','text','none','none','ok,rough,play,service,replace',null,null),
    ('front_wheel','tubeless_status','Estado tubeless delantero','text','none','none','ok,leaking,dry_sealant,not_applicable',null,null),
    ('front_wheel','notes','Notas rueda delantera','text','none','none',null,null,null),
    ('rear_wheel','overall_status','Estado general rueda trasera','text','none','none','ok,attention,critical,unknown',null,null),
    ('rear_wheel','tire_condition','Estado cubierta trasera','text','none','none','ok,worn,damaged,replace',null,null),
    ('rear_wheel','rim_condition','Estado aro trasero','text','none','none','ok,attention,bent,cracked,replace',null,null),
    ('rear_wheel','spoke_condition','Estado rayos traseros','text','none','none','ok,loose,uneven,broken',null,null),
    ('rear_wheel','hub_bearing_condition','Rodamientos maza trasera','text','none','none','ok,rough,play,service,replace',null,null),
    ('rear_wheel','tubeless_status','Estado tubeless trasero','text','none','none','ok,leaking,dry_sealant,not_applicable',null,null),
    ('rear_wheel','notes','Notas rueda trasera','text','none','none',null,null,null),
    ('bottom_bracket','overall_status','Estado general pedalier','text','none','none','ok,attention,critical,unknown',null,null),
    ('bottom_bracket','bearing_condition','Estado rodamientos pedalier','text','none','none','ok,rough,play,service,replace',null,null),
    ('bottom_bracket','noise_status','Ruidos o juego pedalier','text','none','none','ok,creaking,clicking,knocking,service',null,null),
    ('bottom_bracket','notes','Notas pedalier','text','none','none',null,null,null),
    ('cockpit','overall_status','Estado general dirección','text','none','none','ok,attention,critical,unknown',null,null),
    ('cockpit','headset_bearing_condition','Estado rodamientos dirección','text','none','none','ok,rough,play,service,replace',null,null),
    ('cockpit','headset_noise_status','Ruidos o juego dirección','text','none','none','ok,creaking,clicking,knocking,service',null,null),
    ('cockpit','notes','Notas dirección','text','none','none',null,null,null)
  ) registry(section_key, json_key, label, value_type, stored_unit,
    input_units, allowed_values, minimum_value, maximum_value)
$$;

revoke all on function public.assistant_diagnosis_field_registry_internal_v1()
from public, anon, authenticated, service_role;

create or replace function public.assistant_inspect_diagnosis_schema_v1(
  p_section text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare v_authority record; v_items jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.operational') authority;
  if p_section not in ('any','suspension','drivetrain','front_brake','rear_brake',
      'front_wheel','rear_wheel','bottom_bracket','cockpit') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'section', registry.section_key,
    'field', registry.section_key || '.' || registry.json_key,
    'label', registry.label,
    'valueType', registry.value_type,
    'storedUnit', registry.stored_unit,
    'inputUnits', registry.input_units,
    'allowedValues', registry.allowed_values,
    'minimumValue', registry.minimum_value,
    'maximumValue', registry.maximum_value
  ) order by registry.section_key, registry.json_key), '[]'::jsonb)
  into v_items
  from public.assistant_diagnosis_field_registry_internal_v1() registry
  where p_section = 'any' or registry.section_key = p_section;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, false
  );
end;
$$;

create or replace function public.assistant_analyze_sales_period_v1(
  p_basis text,
  p_range_mode text,
  p_relative_period text,
  p_start_date text,
  p_end_date text,
  p_invoice_status text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_timezone text;
  v_business_date date;
  v_start_date date;
  v_end_date date;
  v_item jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.sales') authority;
  if p_basis not in ('issued','collected')
     or p_range_mode not in ('relative','absolute')
     or p_invoice_status not in ('any','open','paid','cancelled') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
  into strict v_timezone from public.tenants tenant
  where tenant.id = v_authority.tenant_id and tenant.is_active is true;
  if not exists (select 1 from pg_timezone_names zone where zone.name = v_timezone) then
    raise exception 'Tenant timezone is invalid' using errcode = '42501';
  end if;
  v_business_date := (statement_timestamp() at time zone v_timezone)::date;
  if p_range_mode = 'relative' then
    if p_relative_period not in ('today','yesterday','this_week','last_week',
        'last_7_days','this_month','last_month','this_year','last_year')
       or p_start_date is not null or p_end_date is not null then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    case p_relative_period
      when 'today' then v_start_date := v_business_date; v_end_date := v_business_date;
      when 'yesterday' then v_start_date := v_business_date - 1; v_end_date := v_business_date - 1;
      when 'this_week' then
        v_start_date := date_trunc('week', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      when 'last_week' then
        v_start_date := date_trunc('week', v_business_date::timestamp)::date - 7;
        v_end_date := date_trunc('week', v_business_date::timestamp)::date - 1;
      when 'last_7_days' then v_start_date := v_business_date - 6; v_end_date := v_business_date;
      when 'this_month' then
        v_start_date := date_trunc('month', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      when 'last_month' then
        v_start_date := (date_trunc('month', v_business_date::timestamp) - interval '1 month')::date;
        v_end_date := date_trunc('month', v_business_date::timestamp)::date - 1;
      when 'this_year' then
        v_start_date := date_trunc('year', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      else
        v_start_date := (date_trunc('year', v_business_date::timestamp) - interval '1 year')::date;
        v_end_date := date_trunc('year', v_business_date::timestamp)::date - 1;
    end case;
  else
    if p_relative_period is not null or p_start_date is null or p_end_date is null
       or p_start_date !~ '^\d{4}-\d{2}-\d{2}$'
       or p_end_date !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    begin v_start_date := p_start_date::date; v_end_date := p_end_date::date;
    exception when others then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end;
    if v_start_date > v_end_date or v_end_date - v_start_date > 366 then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
  end if;

  with invoice_state as materialized (
    select invoice.id, invoice.invoice_number, invoice.customer_name,
      invoice.total, invoice.date, invoice.status,
      case
        when lower(coalesce(invoice.status, '')) in (
          'cancelled','cancelado','cancelada','anulado','anulada'
        ) then 'cancelled'
        when lower(coalesce(invoice.status, '')) in ('paid','pagado','pagada')
          or coalesce(invoice.balance, 0) <= 0 then 'paid'
        else 'open' end normalized_status
    from public.sales_invoices invoice
    where invoice.tenant_id = v_authority.tenant_id
      and lower(coalesce(invoice.status, '')) not in ('draft','borrador')
  ), period_rows as materialized (
    select invoice.id, invoice.invoice_number, invoice.customer_name,
      invoice.total invoice_total,
      case when p_basis = 'issued' then invoice.total
        else coalesce(sum(payment.amount), 0) end period_amount,
      case when p_basis = 'issued' then 1::bigint
        else count(payment.id) end event_count
    from invoice_state invoice
    left join public.sales_payments payment
      on p_basis = 'collected'
     and payment.invoice_id = invoice.id
     and payment.tenant_id = v_authority.tenant_id
     and payment.deleted_at is null and payment.amount > 0
     and (payment.date at time zone v_timezone)::date
       between v_start_date and v_end_date
    where (p_invoice_status = 'any' or invoice.normalized_status = p_invoice_status)
      and (
        (p_basis = 'issued' and (invoice.date at time zone v_timezone)::date
          between v_start_date and v_end_date)
        or p_basis = 'collected'
      )
    group by invoice.id, invoice.invoice_number, invoice.customer_name,
      invoice.total, invoice.date
    having p_basis = 'issued' or count(payment.id) > 0
  ), ranked as materialized (
    select period_rows.id, period_rows.invoice_number,
      period_rows.customer_name, period_rows.invoice_total,
      period_rows.period_amount, period_rows.event_count,
      row_number() over (order by period_amount desc, invoice_total desc,
        invoice_number, id) ordinal
    from period_rows
  ), totals as (
    select count(*)::integer invoice_count,
      coalesce(sum(event_count), 0)::integer event_count,
      coalesce(sum(period_amount), 0) total_amount,
      coalesce(avg(period_amount), 0) average_per_invoice
    from ranked
  )
  select jsonb_build_object(
    'basis', p_basis,
    'startDate', v_start_date,
    'endDate', v_end_date,
    'invoiceStatus', p_invoice_status,
    'invoiceCount', totals.invoice_count,
    'eventCount', totals.event_count,
    'totalAmount', totals.total_amount,
    'averagePerInvoice', totals.average_per_invoice,
    'highestInvoiceId', highest.id,
    'highestInvoiceNumber', highest.invoice_number,
    'highestInvoiceCustomerName', highest.customer_name,
    'highestInvoiceTotal', highest.invoice_total,
    'highestPeriodAmount', highest.period_amount
  ) into v_item
  from totals left join ranked highest on highest.ordinal = 1;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, jsonb_build_array(v_item), false
  );
end;
$$;

create or replace function public.assistant_analyze_cash_and_receivables_v2(
  p_horizon text,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record; v_timezone text; v_business_date date; v_end_date date;
  v_cash_source_status text; v_book_liquid_funds_balance numeric;
  v_cash_account_count integer; v_receivables_source_status text;
  v_receivables_total numeric; v_overdue_receivables numeric;
  v_due_in_horizon_receivables numeric; v_no_due_date_receivables numeric;
  v_open_invoice_count integer; v_overdue_invoice_count integer;
  v_receivable_items jsonb := '[]'::jsonb; v_items jsonb;
  v_has_more boolean := false;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.accounting') authority;
  if p_horizon not in ('today','next_7_days','next_30_days')
     or p_limit not between 1 and 8 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
  into strict v_timezone from public.tenants tenant
  where tenant.id = v_authority.tenant_id and tenant.is_active is true;
  if not exists (select 1 from pg_timezone_names zone where zone.name = v_timezone) then
    raise exception 'Tenant timezone is invalid' using errcode = '42501';
  end if;
  v_business_date := (statement_timestamp() at time zone v_timezone)::date;
  v_end_date := v_business_date + case p_horizon
    when 'today' then 0 when 'next_7_days' then 7 else 30 end;

  begin
    with liquid_accounts as materialized (
      select distinct account.id from public.payment_methods payment_method
      join public.accounts account on account.id = payment_method.account_id
        and account.tenant_id = payment_method.tenant_id
      where payment_method.tenant_id = v_authority.tenant_id
        and payment_method.is_active is true and account.is_active is true
        and account.type = 'asset'
    ), balances as (
      select liquid_account.id,
        coalesce(sum(journal_line.debit_amount - journal_line.credit_amount)
          filter (where journal_entry.id is not null), 0) balance
      from liquid_accounts liquid_account
      left join public.journal_lines journal_line
        on journal_line.tenant_id = v_authority.tenant_id
       and journal_line.account_id = liquid_account.id
      left join public.journal_entries journal_entry
        on journal_entry.id = journal_line.entry_id
       and journal_entry.tenant_id = journal_line.tenant_id
       and lower(journal_entry.status) = 'posted'
       and journal_entry.entry_date <= statement_timestamp()
      group by liquid_account.id
    )
    select count(*)::integer, coalesce(sum(balance), 0)
    into v_cash_account_count, v_book_liquid_funds_balance from balances;
    v_cash_source_status := case when v_cash_account_count = 0
      then 'verifiedEmpty' else 'success' end;
  exception when others then
    v_cash_source_status := 'unavailable'; v_cash_account_count := null;
    v_book_liquid_funds_balance := null;
  end;

  begin
    with payment_totals as materialized (
      select payment.invoice_id, public.clp_round(sum(payment.amount)) amount
      from public.sales_payments payment
      where payment.tenant_id = v_authority.tenant_id and payment.deleted_at is null
      group by payment.invoice_id
    ), credit_totals as materialized (
      select credit.sales_invoice_id invoice_id,
        public.clp_round(sum(credit.total_amount)) amount
      from public.sales_credit_notes credit
      where credit.tenant_id = v_authority.tenant_id and credit.status = 'posted'
      group by credit.sales_invoice_id
    ), refund_totals as materialized (
      select refund.sales_invoice_id invoice_id,
        public.clp_round(sum(refund.amount)) amount
      from public.sales_customer_refunds refund
      where refund.tenant_id = v_authority.tenant_id and refund.status = 'posted'
      group by refund.sales_invoice_id
    ), settlement as materialized (
      select invoice.id entity_id, invoice.invoice_number, invoice.due_date,
        case when invoice.due_date is null then null
          else (invoice.due_date at time zone v_timezone)::date end due_business_date,
        greatest(greatest(public.clp_round(invoice.total)
          - coalesce(credit.amount, 0), 0)
          - greatest(coalesce(payment.amount, 0) - coalesce(refund.amount, 0), 0), 0)
          balance
      from public.sales_invoices invoice
      left join payment_totals payment on payment.invoice_id = invoice.id
      left join credit_totals credit on credit.invoice_id = invoice.id
      left join refund_totals refund on refund.invoice_id = invoice.id
      where invoice.tenant_id = v_authority.tenant_id
        and lower(coalesce(invoice.status, '')) not in (
          'draft','borrador','cancelled','cancelado','cancelada','anulado','anulada'
        )
    ), open_receivables as materialized (
      select settlement.entity_id, settlement.invoice_number,
        settlement.due_date, settlement.due_business_date, settlement.balance,
        case when due_business_date is null then 'no_due_date'
          when due_business_date < v_business_date then 'overdue'
          when due_business_date = v_business_date then 'due_today'
          when due_business_date <= v_end_date then 'due_in_horizon'
          else 'later' end timing,
        case when due_business_date < v_business_date
          then v_business_date - due_business_date else null end days_overdue
      from settlement where balance > 0
    ), numbered as materialized (
      select open_receivables.entity_id, open_receivables.invoice_number,
        open_receivables.due_date, open_receivables.due_business_date,
        open_receivables.balance, open_receivables.timing,
        open_receivables.days_overdue,
        row_number() over (order by
        case timing when 'overdue' then 0 when 'due_today' then 1
          when 'due_in_horizon' then 2 when 'later' then 3 else 4 end,
        due_date nulls last, invoice_number, entity_id) ordinal
      from open_receivables
    )
    select count(*)::integer, coalesce(sum(balance), 0),
      coalesce(sum(balance) filter (where timing = 'overdue'), 0),
      coalesce(sum(balance) filter (where timing in ('due_today','due_in_horizon')), 0),
      coalesce(sum(balance) filter (where timing = 'no_due_date'), 0),
      count(*) filter (where timing = 'overdue')::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'kind','receivable','entityId',entity_id,
        'invoiceNumber',public.assistant_truncate_utf8_internal_v1(invoice_number,100),
        'balance',balance,'dueDate',due_business_date,
        'daysOverdue',days_overdue,'timing',timing
      ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb)
    into v_open_invoice_count, v_receivables_total, v_overdue_receivables,
      v_due_in_horizon_receivables, v_no_due_date_receivables,
      v_overdue_invoice_count, v_receivable_items
    from numbered;
    v_receivables_source_status := case when v_open_invoice_count = 0
      then 'verifiedEmpty' else 'success' end;
    v_has_more := v_open_invoice_count > p_limit;
  exception when others then
    v_receivables_source_status := 'unavailable'; v_receivables_total := null;
    v_overdue_receivables := null; v_due_in_horizon_receivables := null;
    v_no_due_date_receivables := null; v_open_invoice_count := null;
    v_overdue_invoice_count := null; v_receivable_items := '[]'::jsonb;
    v_has_more := false;
  end;
  v_items := jsonb_build_array(jsonb_build_object(
    'kind','summary','asOfDate',v_business_date,'horizon',p_horizon,
    'cashSourceStatus',v_cash_source_status,
    'bookLiquidFundsBalance',v_book_liquid_funds_balance,
    'cashAccountCount',v_cash_account_count,
    'receivablesSourceStatus',v_receivables_source_status,
    'receivablesTotal',v_receivables_total,
    'overdueReceivables',v_overdue_receivables,
    'dueInHorizonReceivables',v_due_in_horizon_receivables,
    'noDueDateReceivables',v_no_due_date_receivables,
    'openInvoiceCount',v_open_invoice_count,
    'overdueInvoiceCount',v_overdue_invoice_count
  )) || v_receivable_items;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_has_more
  );
end;
$$;

revoke all on function public.assistant_query_workshop_jobs_v3(
  text, text, text, text, integer
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_get_workshop_job_context_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_inspect_diagnosis_schema_v1(text)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_analyze_sales_period_v1(
  text, text, text, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_analyze_cash_and_receivables_v2(text, integer)
from public, anon, authenticated, service_role;

grant execute on function public.assistant_query_workshop_jobs_v3(
  text, text, text, text, integer
) to authenticated;
grant execute on function public.assistant_get_workshop_job_context_v1(uuid)
to authenticated;
grant execute on function public.assistant_inspect_diagnosis_schema_v1(text)
to authenticated;
grant execute on function public.assistant_analyze_sales_period_v1(
  text, text, text, text, text, text
) to authenticated;
grant execute on function public.assistant_analyze_cash_and_receivables_v2(text, integer)
to authenticated;

comment on function public.assistant_query_workshop_jobs_v3(
  text, text, text, text, integer
) is 'Resolves workshop candidates across customer, all job bikes and linked invoice while keeping closed lifecycle filters.';
comment on function public.assistant_get_workshop_job_context_v1(uuid) is
  'Exact action context and optimistic revisions for one caller-owned workshop job.';
comment on function public.assistant_inspect_diagnosis_schema_v1(text) is
  'Closed registry of scalar canonical diagnosis fields, input units and allowed values.';
comment on function public.assistant_analyze_sales_period_v1(
  text, text, text, text, text, text
) is 'Server-owned relative or absolute sales analytics. collected is derived only from non-deleted payment events.';
comment on function public.assistant_analyze_cash_and_receivables_v2(text, integer) is
  'Receivables and configured liquid-account book balance using one tenant-timezone lookup instead of per-row authority calls.';

commit;
