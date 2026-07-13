-- ⚠️ DEVELOPMENT TESTING ONLY - DO NOT RUN IN PRODUCTION ⚠️
-- This resets job numbers sequence - breaks accounting compliance in production

-- Option 1: Reset sequence to start from 1 again (deletes ALL jobs)
-- WARNING: This permanently deletes all mechanic jobs and resets counter
DO $$
BEGIN
  -- Delete all jobs (hard delete)
  DELETE FROM mechanic_jobs WHERE tenant_id = public.user_tenant_id();
  
  -- Reset sequence for current tenant
  UPDATE tenants 
  SET job_number_sequence = 0 
  WHERE id = public.user_tenant_id();
  
  RAISE NOTICE '✅ Job numbers reset to start from PG-00001';
END $$;

-- Option 2: Renumber existing jobs to remove gaps (keeps jobs, just renumbers)
-- WARNING: This changes historical job numbers - breaks references
DO $$
DECLARE
  job_rec RECORD;
  new_number INTEGER := 1;
BEGIN
  FOR job_rec IN 
    SELECT id FROM mechanic_jobs 
    WHERE tenant_id = public.user_tenant_id()
    AND deleted_at IS NULL
    ORDER BY created_at, id
  LOOP
    UPDATE mechanic_jobs 
    SET job_number = 'PG-' || LPAD(new_number::text, 5, '0')
    WHERE id = job_rec.id;
    
    new_number := new_number + 1;
  END LOOP;
  
  -- Update sequence to continue from last number
  UPDATE tenants 
  SET job_number_sequence = new_number 
  WHERE id = public.user_tenant_id();
  
  RAISE NOTICE '✅ Jobs renumbered, next will be PG-%', LPAD(new_number::text, 5, '0');
END $$;

-- Option 3: Just fix the sequence to match highest existing number
DO $$
DECLARE
  max_num INTEGER;
BEGIN
  -- Extract highest number from existing jobs
  SELECT COALESCE(MAX(CAST(SUBSTRING(job_number FROM 4) AS INTEGER)), 0)
  INTO max_num
  FROM mechanic_jobs
  WHERE tenant_id = public.user_tenant_id()
  AND job_number ~ '^PG-[0-9]+$';
  
  -- Set sequence to continue from there
  UPDATE tenants 
  SET job_number_sequence = max_num
  WHERE id = public.user_tenant_id();
  
  RAISE NOTICE '✅ Sequence fixed, next will be PG-%', LPAD((max_num + 1)::text, 5, '0');
END $$;

-- ⚠️ REMEMBER: In production, gaps are GOOD - they prove audit trail integrity!
