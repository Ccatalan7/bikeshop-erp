-- Deprecated (Nov 19, 2025)
-- Dual-write mode is no longer necessary because mechanic_job_labor was
-- removed. The entire mechanic job flow now operates solely on
-- mechanic_job_items.

do $$
begin
  raise notice 'PHASE2_DUAL_WRITE_MODE.sql is obsolete: mechanic_job_labor no longer exists.';
end $$;
