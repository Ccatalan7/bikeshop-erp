# 🔧 Bikeshop Module - Troubleshooting Guide

## Common Issues & Solutions

### Issue 1: Cannot view job details from client logbook

**Symptoms:**
- Clicking on a job card shows error
- App crashes when navigating to job details
- Blank page when opening job

**Possible Causes & Fixes:**

#### A. Database foreign key constraint error
```
Error: violates foreign key constraint
```
**Solution:** Verify the job exists in database and has valid `bike_id` and `customer_id`:
```sql
SELECT * FROM mechanic_jobs WHERE id = 'YOUR_JOB_ID';
SELECT * FROM bikes WHERE id = 'BIKE_ID_FROM_JOB';
```

#### B. Missing bike data
```
Error: Cannot read property 'displayName' of null
```
**Solution:** Ensure the bike associated with the job exists:
```sql
-- Check if bike exists
SELECT * FROM bikes WHERE id = (
  SELECT bike_id FROM mechanic_jobs WHERE id = 'YOUR_JOB_ID'
);

-- If bike is missing, update job to use correct bike_id
UPDATE mechanic_jobs 
SET bike_id = 'CORRECT_BIKE_ID' 
WHERE id = 'YOUR_JOB_ID';
```

#### C. Job items query error
```
Error: column "job_id" does not exist
```
**Solution:** Check if `job_items` table exists and has correct schema:
```sql
-- Verify table structure
\d job_items

-- Should have columns: id, job_id, product_id, quantity, unit_price, total_price
```

#### D. Timeline query error
```
Error: relation "mechanic_job_timeline" does not exist
```
**Solution:** The timeline table might not exist. Check `core_schema.sql` and deploy:
```sql
SELECT tablename FROM pg_tables WHERE tablename LIKE '%timeline%';
```

### Issue 2: Photos don't upload

**Symptoms:**
- "Error uploading image" message
- Photos selected but not saved
- Storage bucket error

**Solution:**
1. Create Supabase storage bucket named `bike-images`
2. Enable public access on bucket
3. Add storage policies:
```sql
-- Allow authenticated users to upload
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'bike-images');

-- Allow public read access
CREATE POLICY "Allow public downloads"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'bike-images');
```

### Issue 3: Parts/items not saving

**Symptoms:**
- Parts added but don't appear after save
- "Error adding job item" message

**Solution:**
1. Check `job_items` table exists
2. Verify `product_id` references valid products in `products` table
3. Check for trigger errors in logs

### Issue 4: Timeline not showing

**Symptoms:**
- Timeline section is empty
- No status change history

**Solution:**
1. Verify `mechanic_job_timeline` table exists
2. Check if triggers are creating timeline entries:
```sql
-- Check triggers
SELECT tgname FROM pg_trigger WHERE tgrelid = 'mechanic_jobs'::regclass;

-- Should see: handle_mechanic_job_timeline_trigger
```
3. Manually test trigger:
```sql
UPDATE mechanic_jobs SET status = 'en_progreso' WHERE id = 'YOUR_JOB_ID';
SELECT * FROM mechanic_job_timeline WHERE job_id = 'YOUR_JOB_ID';
```

## Debugging Steps

### 1. Check Database Schema
```bash
# In Supabase SQL Editor, run:
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename LIKE '%bike%' OR tablename LIKE '%job%' OR tablename LIKE '%mechanic%';
```

Expected tables:
- `bikes`
- `mechanic_jobs`
- `job_items`
- `job_labor`
- `mechanic_job_timeline`
- `service_packages` (optional)

### 2. Check Flutter Console
Run app with:
```bash
flutter run -d windows --verbose
```

Look for errors in console when clicking on job.

### 3. Check Supabase Logs
- Go to Supabase Dashboard → Logs
- Look for errors around the time you clicked the job
- Common errors: RLS policy violations, foreign key constraints

### 4. Verify Data Integrity
```sql
-- Check for orphaned jobs (jobs without valid bikes)
SELECT mj.id, mj.job_number, mj.bike_id
FROM mechanic_jobs mj
LEFT JOIN bikes b ON b.id = mj.bike_id
WHERE b.id IS NULL;

-- Check for jobs without customers
SELECT mj.id, mj.job_number, mj.customer_id
FROM mechanic_jobs mj
LEFT JOIN customers c ON c.id = mj.customer_id
WHERE c.id IS NULL;
```

### 5. Re-deploy Schema
If tables or functions are missing:
```bash
# In Supabase SQL Editor, copy entire content of:
# supabase/sql/core_schema.sql
# and execute it
```

## Error Messages Reference

| Error | Likely Cause | Solution |
|-------|--------------|----------|
| `Foreign key violation` | Invalid bike_id or customer_id | Update job with valid IDs |
| `Column does not exist` | Schema not deployed | Deploy core_schema.sql |
| `Permission denied` | RLS policy blocking access | Check RLS policies on tables |
| `Null check operator used on null` | Missing data in database | Verify all required fields exist |
| `Type error` | Data type mismatch | Check if numeric fields have valid numbers |
| `Storage bucket not found` | Bucket not created | Create `bike-images` bucket |

## Getting Help

If issue persists:
1. ✅ Check terminal output for full error stack trace
2. ✅ Share error message with context
3. ✅ Verify database schema is fully deployed
4. ✅ Test with simple data first (minimal job with all required fields)

## Quick Test Checklist

Before reporting an issue, verify:
- [ ] `core_schema.sql` has been deployed to Supabase
- [ ] All tables exist (`bikes`, `mechanic_jobs`, `job_items`, etc.)
- [ ] Sample customer exists in database
- [ ] Sample bike exists linked to customer
- [ ] Job has valid `bike_id` and `customer_id`
- [ ] App is running latest built version
- [ ] No errors in Flutter console
- [ ] Supabase connection is working
