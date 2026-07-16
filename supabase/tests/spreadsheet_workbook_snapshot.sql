begin;

select plan(8);

select has_table('public', 'spreadsheets', 'spreadsheets table exists');
select has_table(
  'public',
  'spreadsheet_cells',
  'legacy spreadsheet cells remain available for one-time migration'
);
select has_column(
  'public',
  'spreadsheets',
  'workbook_data',
  'spreadsheets stores the packaged engine workbook snapshot'
);
select col_type_is(
  'public',
  'spreadsheets',
  'workbook_data',
  'jsonb',
  'workbook_data uses jsonb'
);
select has_trigger(
  'public',
  'spreadsheets',
  'set_spreadsheets_updated_at',
  'spreadsheet snapshot writes update recency'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.spreadsheets'::regclass),
  true,
  'spreadsheets has row-level security enabled'
);
select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheets'
  ),
  4::bigint,
  'spreadsheets has tenant policies for all CRUD operations'
);
select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'spreadsheet_cells'
  ),
  4::bigint,
  'legacy cells retain tenant policies for all CRUD operations'
);

select * from finish();
rollback;
