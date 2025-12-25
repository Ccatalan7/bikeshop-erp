-- SIMPLIFIED FIX: Allow any authenticated user to create support conversations
-- Run this in Supabase SQL Editor

-- First, drop ALL existing conversation insert policies
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;
DROP POLICY IF EXISTS "Customers can create support conversations" ON public.conversations;

-- Create a SIMPLE policy that allows:
-- 1. Employees (has user_profiles record) - can create any conversation
-- 2. Any authenticated user - can create SUPPORT conversations with pending status
CREATE POLICY "Users can create conversations"
  ON public.conversations FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Condition 1: Employee creating any type
    EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
    OR
    -- Condition 2: Anyone can create a support request
    (type = 'support' AND status = 'pending')
  );

-- Also ensure SELECT policy allows creator to see their conversation
DROP POLICY IF EXISTS "Users can view conversations they participate in" ON public.conversations;

CREATE POLICY "Users can view conversations they participate in"
  ON public.conversations FOR SELECT
  TO authenticated
  USING (
    -- Creator can always see their conversation
    created_by = auth.uid()
    OR
    -- Participants can see
    EXISTS (
      SELECT 1 FROM public.conversation_participants
      WHERE conversation_id = conversations.id AND user_id = auth.uid()
    )
    OR
    -- Employees can see all support conversations
    (
      type = 'support' 
      AND EXISTS (
        SELECT 1 FROM public.user_profiles 
        WHERE user_id = auth.uid()
      )
    )
  );
