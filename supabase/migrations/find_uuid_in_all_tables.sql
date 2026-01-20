-- MASTER INVESTIGATION SCRIPT: Find UUID in ANY table
-- This script dynamically searches every table in the database for the UUID.
-- Target UUID: 2599b075-3944-4695-98b7-cde115da4cb9

do $$
declare
  v_target_id uuid := '2599b075-3944-4695-98b7-cde115da4cb9';
  v_table_name text;
  v_exists boolean;
  v_found_any boolean := false;
begin
  raise notice '🕵️‍♂️ Starting Deep Search for UUID: %', v_target_id;

  -- Loop through all tables in public schema
  for v_table_name in 
      select table_name 
      from information_schema.tables 
      where table_schema = 'public' 
      and table_type = 'BASE TABLE'
  loop
    -- Check if table has an 'id' column of type uuid (or text)
    if exists (
        select 1 from information_schema.columns 
        where table_name = v_table_name 
        and column_name = 'id'
    ) then
      -- Execute dynamic query to check existence
      execute format('select exists(select 1 from %I where id::text = $1)', v_table_name)
      into v_exists
      using v_target_id::text;

      if v_exists then
        raise notice '🎯 FOUND MATCH in table: [%]', v_table_name;
        v_found_any := true;
      end if;
    end if;
  end loop;

  if not v_found_any then
    raise notice '❌ UUID not found in any table (checked all public tables with an id column).';
    raise notice '   Possibility: Record was DELETED or ID is not in primary key "id" column.';
  end if;

end $$;
