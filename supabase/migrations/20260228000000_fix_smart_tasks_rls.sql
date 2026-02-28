-- HOTFIX: Fix broken RLS policies and trigger on smart_tasks table.
-- The original migration used wrong function names:
--   - user_tenant_access() → should be public.user_tenant_id()
--   - moddatetime → should be public.set_updated_at()

-- Step 1: Drop ALL broken policies
DROP POLICY IF EXISTS "Users can view tasks in their tenant" ON public.smart_tasks;
DROP POLICY IF EXISTS "Users can insert tasks in their tenant" ON public.smart_tasks;
DROP POLICY IF EXISTS "Users can update tasks in their tenant" ON public.smart_tasks;
DROP POLICY IF EXISTS "Users can delete tasks in their tenant" ON public.smart_tasks;

-- Step 2: Drop broken trigger
DROP TRIGGER IF EXISTS handle_updated_at_smart_tasks ON public.smart_tasks;

-- Step 3: Recreate policies with the CORRECT function (matching core_schema.sql pattern)
CREATE POLICY "Users can view tasks in their tenant"
    ON public.smart_tasks FOR SELECT
    USING (tenant_id = public.user_tenant_id());

CREATE POLICY "Users can insert tasks in their tenant"
    ON public.smart_tasks FOR INSERT
    WITH CHECK (tenant_id = public.user_tenant_id());

CREATE POLICY "Users can update tasks in their tenant"
    ON public.smart_tasks FOR UPDATE
    USING (tenant_id = public.user_tenant_id())
    WITH CHECK (tenant_id = public.user_tenant_id());

CREATE POLICY "Users can delete tasks in their tenant"
    ON public.smart_tasks FOR DELETE
    USING (tenant_id = public.user_tenant_id());

-- Step 4: Recreate trigger with the CORRECT function
CREATE TRIGGER handle_updated_at_smart_tasks
    BEFORE UPDATE ON public.smart_tasks
    FOR EACH ROW
    EXECUTE PROCEDURE public.set_updated_at();
