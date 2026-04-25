begin;

select plan(14);

select has_table('public', 'bike_profiles', 'bike_profiles table exists');
select has_table('public', 'mechanic_job_bikes', 'mechanic_job_bikes table exists');
select has_table('public', 'mechanic_job_items', 'mechanic_job_items table exists');
select has_table('public', 'bike_system_states', 'bike_system_states table exists');
select has_table('public', 'bike_observations', 'bike_observations table exists');
select has_table('public', 'bike_interventions', 'bike_interventions table exists');
select has_table(
  'public',
  'bike_component_lifecycles',
  'bike_component_lifecycles table exists'
);

select has_column(
  'public',
  'mechanic_job_bikes',
  'diagnosis_sheet_data',
  'mechanic_job_bikes stores diagnosis_sheet_data'
);
select has_column(
  'public',
  'mechanic_job_items',
  'service_configuration_data',
  'mechanic_job_items stores service_configuration_data'
);
select has_column(
  'public',
  'mechanic_job_items',
  'system_key',
  'mechanic_job_items stores system_key'
);
select has_column(
  'public',
  'mechanic_job_items',
  'component_slot_key',
  'mechanic_job_items stores component_slot_key'
);

select has_trigger(
  'public',
  'bike_profiles',
  'trg_bike_profiles_updated_at',
  'bike_profiles updated_at trigger exists'
);
select has_trigger(
  'public',
  'mechanic_job_items',
  'trg_mechanic_job_items_change',
  'mechanic_job_items change trigger exists'
);
select has_function(
  'public',
  'create_invoice_from_mechanic_job',
  array['uuid'],
  'create_invoice_from_mechanic_job(uuid) exists'
);

select * from finish();

rollback;
