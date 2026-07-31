-- Versioned success-path control for the payroll deployment mechanism.
-- Executed ONLY against the synthetic local stack by
-- scripts/db/atomicity_rollback_probe.sh; never against a hosted project.
--
-- Same transactional shape as the deployable migrations, without the
-- injected failure: the wrapper must exit 0 and the object must survive.
begin;

create table public._payroll_atomicity_probe_commit(id integer primary key);
insert into public._payroll_atomicity_probe_commit values (1);

commit;
