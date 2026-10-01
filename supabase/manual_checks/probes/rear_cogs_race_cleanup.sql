-- Removes the probe fixture and puts the real product reader back; also run
-- first, in case a failed run left it.
--
-- The reader goes back first, in its own transaction: a failed delete below
-- must not leave the fixture's reader in the local stack (first run,
-- 2026-09-28: a status-transition event still referenced a job and rolled
-- the whole cleanup back, reader included).
do $$
begin
  if to_regclass('probe_rear_cogs.saved_reader') is not null then
    execute (select def from probe_rear_cogs.saved_reader);
  end if;
end;
$$;
drop schema if exists probe_rear_cogs cascade;

-- Finishing a job through its command leaves events, inventory commitments
-- and purchase-list rows; the tenant seed leaves accounts, statuses and
-- settings. Everything with the probe's tenant goes, with the append-only
-- guards and foreign-key triggers off for this transaction only.
begin;
set local session_replication_role = replica;
do $$
declare
  v_table record;
begin
  for v_table in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema
       and t.table_name = c.table_name
       and t.table_type = 'BASE TABLE'
     where c.table_schema = 'public'
       and c.column_name = 'tenant_id'
       and c.table_name <> 'tenants'
  loop
    execute format('delete from public.%I where tenant_id::text = %L',
      v_table.table_name, 'e2830000-0000-4000-8000-000000000001');
  end loop;
end;
$$;
delete from auth.users where id = 'e2830000-0000-4000-8000-000000000099';
delete from public.tenants where id = 'e2830000-0000-4000-8000-000000000001';
commit;
select (select count(*) from public.tenants where id = 'e2830000-0000-4000-8000-000000000001')
       + (select count(*) from public.mechanic_jobs where tenant_id = 'e2830000-0000-4000-8000-000000000001')
       + (select count(*) from public.bikes where tenant_id = 'e2830000-0000-4000-8000-000000000001') as leftover,
       position('spec_active_product_values_internal_v1' in pg_get_functiondef(
         'public.product_bike_fact_spec_internal(uuid,uuid,text)'::regprocedure)) > 0 as real_reader;
