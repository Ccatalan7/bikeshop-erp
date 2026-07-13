-- Updated Nov 19, 2025 for mechanic_job_items-only architecture
-- Uses the canonical public.recalculate_mechanic_job_costs(p_job_id uuid)
-- helper that already lives in supabase/sql/core_schema.sql.

DO $$
DECLARE
  v_job_id uuid;
BEGIN
  FOR v_job_id IN (SELECT id FROM mechanic_jobs)
  LOOP
    PERFORM public.recalculate_mechanic_job_costs(v_job_id);
  END LOOP;
  RAISE NOTICE 'Recalculated costs for % jobs', (SELECT count(*) FROM mechanic_jobs);
END $$;
