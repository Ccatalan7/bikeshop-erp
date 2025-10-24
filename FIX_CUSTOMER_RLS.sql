-- ============================================================================
-- FIX CUSTOMER SIGNUP RLS ISSUE
-- Run this in Supabase SQL Editor
-- ============================================================================

-- First, check current policies
SELECT schemaname, tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'customers';

-- Drop all existing policies on customers table
DROP POLICY IF EXISTS "Authenticated customers read" ON customers;
DROP POLICY IF EXISTS "Customers can create own profile" ON customers;
DROP POLICY IF EXISTS "Customers can update own profile" ON customers;
DROP POLICY IF EXISTS "Allow authenticated read" ON customers;
DROP POLICY IF EXISTS "Allow users to insert own customer record" ON customers;
DROP POLICY IF EXISTS "Allow users to update own customer record" ON customers;
DROP POLICY IF EXISTS "Admins read all" ON customers;
DROP POLICY IF EXISTS "Authenticated users can delete customers" ON customers;
DROP POLICY IF EXISTS "Authenticated users can insert customers" ON customers;
DROP POLICY IF EXISTS "Authenticated users can read customers" ON customers;
DROP POLICY IF EXISTS "Authenticated users can update customers" ON customers;
DROP POLICY IF EXISTS "customers_insert_policy" ON customers;
DROP POLICY IF EXISTS "customers_select_policy" ON customers;
DROP POLICY IF EXISTS "customers_update_policy" ON customers;

-- Create new policies with correct permissions
-- 1. Allow authenticated users to read all customers (for admin/ERP)
CREATE POLICY "customers_select_policy" 
  ON customers
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- 2. Allow authenticated users to INSERT their own customer record
CREATE POLICY "customers_insert_policy"
  ON customers
  FOR INSERT
  WITH CHECK (auth.uid() = auth_user_id);

-- 3. Allow users to UPDATE their own customer record
CREATE POLICY "customers_update_policy"
  ON customers
  FOR UPDATE
  USING (auth.uid() = auth_user_id)
  WITH CHECK (auth.uid() = auth_user_id);

-- Verify the policies were created
SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'customers'
ORDER BY policyname;

-- Test what auth.uid() returns (run this while logged in)
SELECT auth.uid() as current_user_id;

-- Check if auth_user_id column exists and its type
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'customers' AND column_name = 'auth_user_id';
