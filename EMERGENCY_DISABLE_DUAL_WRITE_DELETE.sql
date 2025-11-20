-- Deprecated (Nov 19, 2025)
-- The mechanic_job_labor table and its dual-write triggers were removed as part of
-- the smart pegas 1.0 migration. This helper is intentionally disabled to
-- prevent re-applying legacy patches.

do $$
begin
	raise notice 'EMERGENCY_DISABLE_DUAL_WRITE_DELETE.sql is obsolete: mechanic_job_labor no longer exists.';
end $$;
