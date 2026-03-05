-- Fix missing RLS policies for accounts table (Chart of Accounts)
-- Error: new row violates row-level security policy for table "accounts" (code 42501)

-- Ensure RLS is enabled
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any (idempotent)
DROP POLICY IF EXISTS "Authenticated users can read accounts" ON public.accounts;
DROP POLICY IF EXISTS "Authenticated users can insert accounts" ON public.accounts;
DROP POLICY IF EXISTS "Authenticated users can update accounts" ON public.accounts;
DROP POLICY IF EXISTS "Authenticated users can delete accounts" ON public.accounts;

-- Recreate all four policies
CREATE POLICY "Authenticated users can read accounts"
  ON public.accounts FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert accounts"
  ON public.accounts FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update accounts"
  ON public.accounts FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete accounts"
  ON public.accounts FOR DELETE
  USING (auth.role() = 'authenticated');
