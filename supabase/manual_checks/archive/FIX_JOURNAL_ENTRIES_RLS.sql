-- Fix RLS policies for journal_entries and journal_lines
-- The problem: Missing "to authenticated" clause in DELETE policies

-- Drop old policies
drop policy if exists "journal_entries_delete" on journal_entries;
drop policy if exists "journal_lines_delete" on journal_lines;

-- Recreate with "to authenticated"
create policy "journal_entries_delete" on journal_entries 
  for delete 
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "journal_lines_delete" on journal_lines 
  for delete 
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Verify policies exist
SELECT 
  tablename, 
  policyname, 
  roles, 
  cmd 
FROM pg_policies 
WHERE tablename IN ('journal_entries', 'journal_lines')
  AND cmd = 'DELETE'
ORDER BY tablename;
