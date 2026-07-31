-- Versioned atomicity probe for the payroll deployment mechanism.
-- Executed ONLY against the synthetic local stack by
-- scripts/db/atomicity_rollback_probe.sh; never against a hosted project.
--
-- Shape mirrors the deployable payroll migrations: one explicit transaction,
-- several DDL objects, and a deliberate failure BETWEEN two objects. The
-- wrapper (query.sh --write --file → psql -f with ON_ERROR_STOP=1) must exit
-- non-zero and leave NO object behind.
begin;

create table public._payroll_atomicity_probe_first(id integer primary key);
insert into public._payroll_atomicity_probe_first values (1);

do $$
begin
  raise exception 'atomicity probe: deliberate failure between two objects';
end
$$;

-- Never reached: proves the failure interrupts the file mid-transaction.
create table public._payroll_atomicity_probe_second(id integer primary key);

commit;
