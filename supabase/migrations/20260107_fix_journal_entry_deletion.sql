-- Fix RLS policies for deleting journal entries and lines
-- Problem: Deletion might be failing silently due to missing or restrictive policies

-- Journal Entries
DROP POLICY IF EXISTS "Authenticated users can delete journal_entries" ON public.journal_entries;

CREATE POLICY "Authenticated users can delete journal_entries"
  ON public.journal_entries FOR DELETE
  USING (auth.role() = 'authenticated');

-- Journal Lines
DROP POLICY IF EXISTS "Authenticated users can delete journal_lines" ON public.journal_lines;

CREATE POLICY "Authenticated users can delete journal_lines"
  ON public.journal_lines FOR DELETE
  USING (auth.role() = 'authenticated');
