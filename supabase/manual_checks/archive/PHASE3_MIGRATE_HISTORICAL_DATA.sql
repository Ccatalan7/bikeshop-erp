-- Deprecated (Nov 19, 2025)
-- Historical labor migration is no longer required because
-- mechanic_job_labor was removed and data now lives solely in
-- mechanic_job_items.

DO $$
BEGIN
  RAISE NOTICE 'PHASE3_MIGRATE_HISTORICAL_DATA.sql is obsolete: mechanic_job_labor no longer exists.';
END $$;
