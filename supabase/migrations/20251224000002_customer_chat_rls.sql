-- Fix RLS policy to allow CUSTOMERS to create support conversations
-- Issue: Current policy requires tenant_id = user_tenant_id(), but customers don't have user_profiles

-- 1. Drop and recreate INSERT policy for conversations
DROP POLICY IF EXISTS "Users can create conversations" ON public.conversations;

CREATE POLICY "Users can create conversations"
  ON public.conversations FOR INSERT
  TO authenticated
  WITH CHECK (
    -- Employee: must match their tenant
    (tenant_id = public.user_tenant_id())
    OR
    -- Customer: Can create support conversations for any valid tenant
    (
      type = 'support' 
      AND status = 'pending'
      AND tenant_id IS NOT NULL
      AND public.user_tenant_id() IS NULL  -- This means they're a customer (no user_profiles entry)
    )
  );

-- 2. Update the SELECT policy to let customers see their own conversations
DROP POLICY IF EXISTS "Users can view conversations they participate in" ON public.conversations;

CREATE POLICY "Users can view conversations they participate in"
  ON public.conversations FOR SELECT
  TO authenticated
  USING (
    public.is_conversation_participant(id)
    OR
    created_by = auth.uid()
    OR
    ( -- Employees can view support tickets even if not explicitly a participant yet
      type = 'support' AND 
      EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid() AND role IN ('admin', 'manager', 'cashier', 'mechanic', 'accountant'))
    )
  );

-- 3. Fix conversation_participants INSERT policy for customers
DROP POLICY IF EXISTS "Participants can add themselves" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can add themselves as participants" ON public.conversation_participants;

CREATE POLICY "Users can add themselves as participants"
  ON public.conversation_participants FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()  -- Can only add yourself
    OR
    EXISTS (  -- Or employees can add anyone
      SELECT 1 FROM public.user_profiles 
      WHERE user_id = auth.uid() 
      AND role IN ('admin', 'manager', 'cashier', 'mechanic')
    )
  );

-- 4. Ensure messages INSERT policy works for customers too
DROP POLICY IF EXISTS "Users can send messages" ON public.messages;

CREATE POLICY "Users can send messages"
  ON public.messages FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND
    (
      -- Participants can send
      EXISTS (
        SELECT 1 FROM public.conversation_participants
        WHERE conversation_id = messages.conversation_id
        AND user_id = auth.uid()
      )
      OR
      -- Creator can send (before being added as participant)
      EXISTS (
        SELECT 1 FROM public.conversations
        WHERE id = messages.conversation_id
        AND created_by = auth.uid()
      )
    )
  );
