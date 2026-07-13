# ✅ Task Schema Cleanup - COMPLETE

## Problem Summary
- Database had conflicting task trigger definitions
- **OLD triggers** tried to insert with columns: `task_type`, `title`, `status`, `job_item_id`, `job_labor_id`
- **NEW schema** only has: `task_name`, `is_completed`, `parent_item_id`, `parent_labor_id`
- Error: `column 'task_type' of relation 'mechanic_job_tasks' does not exist`

## Root Cause
**OLD trigger function definitions at lines 9744-9978 in core_schema.sql**:
- `auto_create_task_for_job_item()` - Created tasks with old columns
- `auto_create_task_for_job_labor()` - Created tasks with old columns
- `sync_tasks_with_job_status()` - Updated tasks using old status column
- `get_job_task_summary()` - Queried old status column
- Triggers: `trg_auto_create_task_for_item`, `trg_auto_create_task_for_labor`, `trg_sync_tasks_with_job_status`

These were being RECREATED after the cleanup section dropped them.

## Solution Applied
**Removed lines 9744-9978 from core_schema.sql** containing all old trigger function definitions.

**File now has**:
- ✅ Cleanup section at top (lines 7-66) - Drops any lingering old triggers
- ✅ NEW smart task schema (lines 9377-9600)
- ✅ Deprecation notice (lines 9726-9741) - Documents what was removed
- ✅ NEW trigger system (lines ~11889+) - `auto_parse_item_description` trigger

**Verified**:
- ❌ NO `create trigger trg_auto_create_task_for` statements
- ❌ NO `function public.auto_create_task_for_job` definitions
- ✅ NEW trigger `trg_auto_parse_item_description` exists (line 11889)

## Deployment Instructions

### 1. Deploy Updated Schema
```sql
-- Copy ENTIRE core_schema.sql file to Supabase SQL Editor
-- Run it (this will drop old triggers and install new ones)
```

### 2. Hot Reload Flutter App
```bash
# Press 'r' in terminal running flutter app
# OR restart app completely
```

### 3. Test All Dialogs
- ✅ Add Product from Tasks tab
- ✅ Add Service from Tasks tab
- ✅ Add Standalone Task
- ✅ Add Sub-Task
- ✅ Remove items
- ✅ Toggle task completion

### Expected Result
**No more errors!** All database operations should succeed.

## What Changed in Database

**OLD system (REMOVED)**:
```sql
-- When product added → auto_create_task_for_job_item() fired
-- Tried to INSERT:
INSERT INTO mechanic_job_tasks (
  tenant_id, job_id, job_item_id, -- ❌ job_item_id doesn't exist
  task_type, title, status         -- ❌ These columns don't exist
) VALUES (...);
```

**NEW system (NOW ACTIVE)**:
```sql
-- When product/service added → auto_parse_item_description() fires
-- Parses description bullet points
-- Creates tasks with:
INSERT INTO mechanic_job_tasks (
  tenant_id, job_id, parent_item_id, -- ✅ Correct column
  task_name, is_completed             -- ✅ Correct columns
) VALUES (...);
```

## Verification Queries (Optional)

```sql
-- Check no old triggers exist
SELECT tgname 
FROM pg_trigger 
WHERE tgname LIKE '%auto_create_task_for%';
-- Expected: 0 rows

-- Check new trigger exists
SELECT tgname 
FROM pg_trigger 
WHERE tgname = 'trg_auto_parse_item_description';
-- Expected: 1 row

-- Check task table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'mechanic_job_tasks' 
  AND column_name IN ('task_name', 'is_completed', 'parent_item_id', 'task_type', 'title', 'status');
-- Expected: task_name, is_completed, parent_item_id (NEW columns only)
-- Should NOT show: task_type, title, status
```

## Files Modified
- ✅ `supabase/sql/core_schema.sql` - Removed lines 9744-9978 (old trigger definitions)

## Files Created (Reference Only)
- `supabase/manual_checks/archive/FIX_TASK_SCHEMA_CONFLICT.sql` - Historical standalone rollout (do not run)
- `supabase/manual_checks/recovery/EMERGENCY_DROP_TRIGGERS.sql` - Quarantined destructive recovery evidence (do not run directly)
- `TASK_SCHEMA_CLEANUP_COMPLETE.md` - This file

## If Errors Persist After Deployment

Do not run the archived emergency script directly. Diagnose current trigger
state read-only, follow the production incident runbook, take a backup, and use
the governed schema/migration workflow.

2. **Check trigger list**:
```sql
SELECT tgname, tgrelid::regclass 
FROM pg_trigger 
WHERE tgname LIKE '%task%' 
  AND tgisinternal = false;
```

3. **Manual cleanup if needed**:
```sql
DROP TRIGGER IF EXISTS trg_auto_create_task_for_item ON mechanic_job_items;
DROP TRIGGER IF EXISTS trg_auto_create_task_for_labor ON mechanic_job_labor;
DROP TRIGGER IF EXISTS trg_sync_tasks_with_job_status ON mechanic_jobs;
DROP FUNCTION IF EXISTS public.auto_create_task_for_job_item();
DROP FUNCTION IF EXISTS public.auto_create_task_for_job_labor();
DROP FUNCTION IF EXISTS public.sync_tasks_with_job_status();
DROP FUNCTION IF EXISTS public.get_job_task_summary(uuid);
```

## Summary
✅ Old trigger definitions **COMPLETELY REMOVED** from core_schema.sql  
✅ Cleanup section prevents recreation  
✅ NEW smart task system ready to use  
✅ Ready for deployment  

**Next step**: Deploy core_schema.sql to Supabase SQL Editor
